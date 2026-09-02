const std = @import("std");
const rl = @import("raylib");

const envmod = @import("../world/env.zig");
const gfx = @import("../gfx/gfx.zig");
const hud = @import("hud.zig");
const mathx = @import("../core/mathx.zig");
const props = @import("../props/props.zig");
const ui = @import("ui.zig");
const tune = @import("../play/tune.zig");
const tuneui = @import("tuneui.zig");
const icons = @import("icons.zig");
const item = @import("../play/item.zig");
const itemart = @import("itemart.zig");
const wf = @import("../world/worldfmt.zig");
const frogmod = @import("../foes/frog.zig");
const archermod = @import("../foes/archer.zig");
const ogremod = @import("../foes/ogre.zig");
const koboldmod = @import("../foes/kobold.zig");
const broodmod = @import("../foes/brood.zig");
const warriormod = @import("../foes/warrior.zig");
const shademod = @import("../foes/shade.zig");
const leechmod = @import("../foes/leechfly.zig");
const rootedmod = @import("../foes/rooted.zig");
const shroommod = @import("../foes/shroom.zig");
const knightmod = @import("../foes/knight.zig");
const delvermod = @import("../foes/delver.zig");
const necromod = @import("../foes/necro.zig");
const deermod = @import("../foes/fungaldeer.zig");
const magemod = @import("../foes/shroommage.zig");
const golemmod = @import("../foes/sporegolem.zig");
const fenmod = @import("../foes/fenlurker.zig");
const skittermod = @import("../foes/skitterer.zig");
const priestmod = @import("../foes/ancientpriest.zig");
const hollowmod = @import("../foes/hollow.zig");
const bloommod = @import("../foes/slumberbloom.zig");
const cindermod = @import("../foes/cinderwake.zig");
const gorgermod = @import("../foes/rotgorger.zig");
const birchmod = @import("../foes/birchwight.zig");
const huskmod = @import("../foes/salthusk.zig");
const fishmod = @import("../foes/fishman.zig");
const batmod = @import("../foes/blinkbat.zig");
const owlbearmod = @import("../foes/owlbear.zig");
const duomod = @import("../foes/fungalduo.zig");
const combat = @import("../play/combat.zig");
const foemod = @import("../foes/foe.zig");
const elemfx = @import("../gfx/elemfx.zig");

const v3 = mathx.v3;
const Kind = props.Kind;


pub const Shelf = enum {
    decor,
    props,
    interact,

    pub fn kinds(s: Shelf) []const Kind {
        return switch (s) {
            .decor => &props.FLORA_KINDS,
            .props => &props.SOLID_KINDS,
            .interact => &props.INTERACT_KINDS,
        };
    }

    pub fn label(s: Shelf) [:0]const u8 {
        return switch (s) {
            .decor => "Decor",
            .props => "Props",
            .interact => "Interactables",
        };
    }

    fn of(k: Kind) Shelf {
        return switch (props.stock(k)) {
            .decor => .decor,
            .props => .props,
            .interact => .interact,
        };
    }
};

const Pose = struct {
    yaw: f32 = BASE_YAW,
    pitch: f32 = BASE_PITCH,
    zoom: f32 = 1.0,
};

const BASE_YAW: f32 = 0.62;
const BASE_PITCH: f32 = 0.34;
const MIN_PITCH: f32 = -0.12;
const MAX_PITCH: f32 = 1.35;
const MIN_ZOOM: f32 = 0.45;
const MAX_ZOOM: f32 = 4.0;
const ROT_RATE: f32 = 0.008; // radians per pixel of drag
const CLICK_SLOP = ui.DRAG_PX;
const ZOOM_RATE: f32 = 0.12;

const FIT: f32 = 2.05;

const BACKDROP = mathx.rgba(52, 48, 40, 255);

const THUMB_W: i32 = 236;
const THUMB_H: i32 = 198;
const BIG_W: i32 = 1000;
const BIG_H: i32 = 700;

var thumbRT: ?rl.RenderTexture2D = null;
var bigRT: ?rl.RenderTexture2D = null;

fn target(slot: *?rl.RenderTexture2D, w: i32, h: i32) rl.RenderTexture2D {
    if (slot.* == null) slot.* = rl.loadRenderTexture(w, h) catch @panic("objview: render target");
    return slot.*.?;
}

pub fn unload() void {
    if (thumbRT) |t| rl.unloadRenderTexture(t);
    if (bigRT) |t| rl.unloadRenderTexture(t);
    thumbRT = null;
    bigRT = null;
    if (charSet) |cs| std.heap.c_allocator.destroy(cs);
    charSet = null;
}

pub const Mode = enum {
    objects,
    icons,
    chars,
    effects,
    volumes,

    fn label(m: Mode) [:0]const u8 {
        return switch (m) {
            .objects => "Objects",
            .icons => "Icons",
            .chars => "Characters",
            .effects => "Effects",
            .volumes => "Gas & AOE",
        };
    }
};

const Volume = enum {
    spore_cloud,
    acid_pool,
    knight_gas,

    fn label(v: Volume) [:0]const u8 {
        return switch (v) {
            .spore_cloud => "Sporeling cloud",
            .acid_pool => "Broodling acid",
            .knight_gas => "Bone knight gas",
        };
    }
    fn loop(v: Volume) f32 {
        return switch (v) {
            .spore_cloud => shroommod.CLOUD_LIFE + 0.8,
            .acid_pool => broodmod.ACID_LIFE + 0.8,
            .knight_gas => knightmod.GAS_LIFE + 0.8,
        };
    }
};

/// **THE FX BENCH — `elemfx`'s twelve cells, PLAYING.** The jukebox's arrangement one gallery along: the sounds are auditioned there because a waveform on a page tells you nothing, and `lifeHi 1.15` is not a thing anybody can picture. Four elements against three verbs, side by side and on a loop.
const Verb = enum {
    gather,
    burst,
    pour,

    fn label(v: Verb) [:0]const u8 {
        return switch (v) {
            .gather => "Gather",
            .burst => "Burst",
            .pour => "Pour",
        };
    }
    fn loop(v: Verb) f32 {
        return switch (v) {
            .gather => 0.9,
            .burst => 1.1,
            .pour => 0,
        };
    }
};

const BENCH_FX_N = blk: {
    var life: f32 = 0;
    for (std.meta.tags(combat.Elem)) |e| life = @max(life, elemfx.sig(e).lifeHi);
    const worst = @as(f32, @floatFromInt(elemfx.pourCount(1))) * elemfx.POUR_RATE * life;
    break :blk @as(usize, @intFromFloat(@ceil(worst))) + 32;
};
/// …and the hitch ceiling on ONE frame of it — `elemfx.POUR_CAP`, the same number the fight runs at, because a bench throttled differently from the thing it is tuning is a bench that lies. As a bare `8` it was UNDER what a 60 fps frame owes at `POUR_RATE` (9.3), so it was in permanent hitch: drawing a stream at 480 motes a second against the fight's 560.
const BENCH_POUR_CAP: usize = elemfx.POUR_CAP;
const BENCH_AT = v3(0, 1.05, 0);
const BENCH_DIR = v3(0, 0, -1);

const CHAR_KINDS = blk: {
    const all = @typeInfo(wf.FoeKind).@"enum".fields;
    var out: [all.len - 1]wf.FoeKind = undefined;
    var n: usize = 0;
    for (all) |f| {
        const k: wf.FoeKind = @enumFromInt(f.value);
        if (k == .brood_sac) continue;
        out[n] = k;
        n += 1;
    }
    break :blk out;
};
const CHAR_N = CHAR_KINDS.len;

pub fn charSlot(k: wf.FoeKind) ?usize {
    for (CHAR_KINDS, 0..) |c, i| {
        if (c == k) return i;
    }
    return null;
}

/// An item's picture in the icon gallery — past the editor glyphs, in `item.Kind` order.
pub fn itemSlot(k: item.Kind) usize {
    return GLYPH_N + @intFromEnum(k);
}

const GLYPH_N = @typeInfo(icons.Icon).@"enum".fields.len;
const PICT_N = item.NK;
const ICONS_TOTAL = GLYPH_N + PICT_N;

pub const State = struct {
    mode: Mode = .objects,
    shelf: Shelf = .props,
    page: i32 = 0,
    open: ?Kind = null,
    openIcon: ?usize = null,
    openChar: ?usize = null,
    pose: [props.NK]Pose = [_]Pose{.{}} ** props.NK,
    charPose: [CHAR_N]Pose = [_]Pose{.{}} ** CHAR_N,
    grabbed: ?usize = null,
    travel: f32 = 0,
    elem: combat.Elem = .cold,
    verb: Verb = .pour,
    fxPose: Pose = .{},
    vol: Volume = .spore_cloud,
    volPose: Pose = .{},
    volT: f32 = 0,
    volCloud: shroommod.Cloud = .{},
    volPool: broodmod.Pool = .{},
    volGas: knightmod.Gas = .{},
    fx: [BENCH_FX_N]foemod.Particle = [_]foemod.Particle{.{}} ** BENCH_FX_N,
    fxHead: usize = 0,
    fxT: f32 = 0,
    fxAcc: f32 = 0,

    pub fn poseOf(self: *State, k: Kind) *Pose {
        return &self.pose[@intFromEnum(k)];
    }

    pub fn show(self: *State, k: Kind) void {
        self.shelf = Shelf.of(k);
        self.open = k;
        self.grabbed = null;
        const list = self.shelf.kinds();
        for (list, 0..) |kk, i| {
            if (kk == k) {
                self.page = @intCast(@divTrunc(@as(i32, @intCast(i)), perPage()));
                break;
            }
        }
    }
};


fn camFor(nfo: *const props.Info, pose: Pose, aspect: f32) rl.Camera3D {
    return fitCam(nfo.top, nfo.bound, pose, aspect);
}

fn fitCam(top: f32, bound: f32, pose: Pose, aspect: f32) rl.Camera3D {
    const reach = mathx.maxF(mathx.maxF(top * 0.8, bound * 0.5), 0.45);
    const fit = reach * FIT / mathx.maxF(mathx.minF(aspect, 1.0), 0.55);
    const dist = fit / mathx.clampF(pose.zoom, MIN_ZOOM, MAX_ZOOM);
    const focus = v3(0, top * 0.42, 0);
    const cp = mathx.cosf(pose.pitch);
    return .{
        .position = v3(
            focus.x + mathx.sinf(pose.yaw) * cp * dist,
            focus.y + mathx.sinf(pose.pitch) * dist,
            focus.z + mathx.cosf(pose.yaw) * cp * dist,
        ),
        .target = focus,
        .up = v3(0, 1, 0),
        .fovy = 42,
        .projection = .perspective,
    };
}

fn rtAspect(rt: rl.RenderTexture2D) f32 {
    return @as(f32, @floatFromInt(rt.texture.width)) / @as(f32, @floatFromInt(rt.texture.height));
}

fn openStage(rt: rl.RenderTexture2D, env: *envmod.Env, scene: *gfx.Scene, cam: rl.Camera3D, aspect: f32) void {
    rl.beginTextureMode(rt);
    rl.clearBackground(BACKDROP);
    rl.beginMode3D(cam);
    scene.bind(cam.position);
    scene.shadowsOff();
    scene.setLights(&.{});
    scene.setGround(true);
    const view = envmod.View.fromCamera(cam, aspect);
    env.drawGround(&view);
    scene.setGround(false);
}

fn closeStage() void {
    rl.endMode3D();
    rl.endTextureMode();
}

fn render(rt: rl.RenderTexture2D, env: *envmod.Env, scene: *gfx.Scene, kind: Kind, pose: Pose) void {
    const nfo = props.info(kind);
    const aspect = rtAspect(rt);
    openStage(rt, env, scene, camFor(nfo, pose, aspect), aspect);
    scene.setWind(nfo.flora);
    rl.drawModel(env.model(kind), mathx.zero3, 1.0, rl.Color.white);
    if (env.veil(kind)) |v| rl.drawModel(v, mathx.zero3, 1.0, rl.Color.white);
    scene.setWind(false);
    closeStage();
}

// ONE GROUP OF EACH, exactly as the game holds them — the group is every creature's own draw contract (model, flash, scale), so the viewer cannot drift from what the field shows. Members are respawned into slot 0 per render; a spawn poses before it returns, so the cell is the creature's own first frame.
pub const CharSet = struct {
    warren: frogmod.Knot,
    line: archermod.Line,
    grief: ogremod.Grief,
    band: koboldmod.Warband,
    brood: broodmod.Brood,
    muster: warriormod.Muster,
    haunt: shademod.Haunt,
    swarm: leechmod.Swarm,
    grove: rootedmod.Grove,
    cluster: shroommod.Cluster,
    warrens: delvermod.Warrens,
    rite: necromod.Rite,
    vigil: knightmod.Vigil,
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
    vanguard: duomod.Vanguard,
    conclave: duomod.Conclave,
};
/// One group per creature, so it GROWS WITH THE ROSTER and is measured by the test at the foot of this file: as
/// a figure it read 112.4 MB and was 150.6 by the time anyone looked.
var charSet: ?*CharSet = null;

pub const CHAR_GROUPS = @typeInfo(CharSet).@"struct".fields.len;

fn ensureChars(scene: *gfx.Scene) *CharSet {
    if (charSet) |cs| return cs;
    const cs = std.heap.c_allocator.create(CharSet) catch @panic("objview: character roster");
    charSet = cs;
    cs.warren = frogmod.Knot.init(scene.shader);
    cs.line = archermod.Line.init(scene.shader);
    cs.grief = ogremod.Grief.init(scene.shader);
    cs.band = koboldmod.Warband.init(scene.shader);
    cs.brood = broodmod.Brood.init(scene.shader);
    cs.muster = warriormod.Muster.init(scene.shader);
    cs.haunt = shademod.Haunt.init(scene.shader);
    cs.swarm = leechmod.Swarm.init(scene.shader);
    cs.grove = rootedmod.Grove.init(scene.shader);
    cs.cluster = shroommod.Cluster.init(scene.shader);
    cs.warrens = delvermod.Warrens.init(scene.shader);
    cs.rite = necromod.Rite.init(scene.shader);
    cs.vigil = knightmod.Vigil.init(scene.shader);
    cs.herd = deermod.Herd.init(scene.shader);
    cs.ring = magemod.Ring.init(scene.shader);
    cs.host = golemmod.Host.init(scene.shader);
    cs.marsh = fenmod.Marsh.init(scene.shader);
    cs.clatter = skittermod.Clatter.init(scene.shader);
    cs.crypt = priestmod.Crypt.init(scene.shader);
    cs.belfry = hollowmod.Belfry.init(scene.shader);
    cs.bed = bloommod.Bed.init(scene.shader);
    cs.scorch = cindermod.Scorch.init(scene.shader);
    cs.gorge = gorgermod.Gorge.init(scene.shader);
    cs.stand = birchmod.Stand.init(scene.shader);
    cs.pan = huskmod.Pan.init(scene.shader);
    cs.shoal = fishmod.Shoal.init(scene.shader);
    cs.roost = batmod.Roost.init(scene.shader);
    cs.perch = owlbearmod.Perch.init(scene.shader);
    cs.vanguard = duomod.Vanguard.init(scene.shader);
    cs.conclave = duomod.Conclave.init(scene.shader);
    inline for (@typeInfo(CharSet).@"struct".fields) |f| @field(cs, f.name).n = 0;
    return cs;
}

fn charDims(k: wf.FoeKind) struct { top: f32, bound: f32 } {
    return switch (k) {
        .toad => .{ .top = 1.7, .bound = 1.6 },
        .archer => .{ .top = 2.0, .bound = 1.0 },
        .ogre => .{ .top = 4.5, .bound = 2.4 },
        .berserker, .priest, .slinger => .{ .top = 1.7, .bound = 1.0 },
        .brood_mother => .{ .top = 2.8, .bound = 2.9 },
        .broodling => .{ .top = 1.2, .bound = 1.1 },
        .brood_sac => .{ .top = 1.2, .bound = 1.0 },
        .shieldman, .greatsword => .{ .top = 2.1, .bound = 1.2 },
        .shade => .{ .top = 2.4, .bound = 1.2 },
        // The same rig at `shade.SPEC`'s own 1.28, so the viewer frames the body it draws.
        .mourner => .{ .top = 3.1, .bound = 1.6 },
        .slumber_bloom => .{ .top = 1.6, .bound = 1.3 },
        .cinder_wake => .{ .top = 1.9, .bound = 1.2 },
        .rotgorger => .{ .top = 1.5, .bound = 1.9 },
        .birchwight => .{ .top = 2.4, .bound = 1.4 },
        .salt_husk => .{ .top = 1.9, .bound = 1.2 },
        .fish_spearman, .fish_netter, .fish_shaman => .{ .top = 2.3, .bound = 1.3 },
        .blinkbat => .{ .top = 4.2, .bound = 3.2 },
        .owlbear => .{ .top = 3.0, .bound = 1.9 },
        .leechfly => .{ .top = 2.9, .bound = 1.8 },
        .rooted => .{ .top = 7.2, .bound = 3.6 },
        .shroom => .{ .top = 1.2, .bound = 1.0 },
        .bone_knight => .{ .top = 5.4, .bound = 3.2 },
        .delver => .{ .top = 1.9, .bound = 2.0 },
        .necromancer => .{ .top = 2.8, .bound = 1.3 },
        .fungal_deer => .{ .top = 2.6, .bound = 2.4 },
        .mushroom_mage => .{ .top = 1.6, .bound = 1.4 },
        .spore_golem => .{ .top = 3.3, .bound = 2.6 },
        .fen_lurker => .{ .top = 2.9, .bound = 1.1 },
        .bone_skitterer => .{ .top = 2.2, .bound = 1.4 },
        .ancient_priest => .{ .top = 3.4, .bound = 1.4 },
        .tolling_hollow => .{ .top = 2.9, .bound = 1.9 },
        // Both on the shared 1.34 rig, and the swordsman's bound is the SWORD held out to one side.
        .fungal_swordsman => .{ .top = 3.0, .bound = 2.6 },
        .fungal_magus => .{ .top = 3.2, .bound = 1.6 },
    };
}

fn drawChar(cs: *CharSet, k: wf.FoeKind, scene: *gfx.Scene) void {
    const seed = 0.35;
    switch (k) {
        .toad => {
            cs.warren.n = 1;
            cs.warren.live()[0] = frogmod.Frog.spawn(mathx.zero3, 0, 1.0, seed);
            cs.warren.draw(scene);
        },
        .archer => {
            cs.line.n = 1;
            cs.line.live()[0] = archermod.Archer.spawn(mathx.zero3, 0, 1.0, seed);
            cs.line.draw(scene);
        },
        .ogre => {
            cs.grief.n = 1;
            cs.grief.live()[0] = ogremod.Ogre.spawn(mathx.zero3, 0, 1.0, seed);
            cs.grief.draw(scene);
        },
        .berserker, .priest, .slinger => {
            const role: koboldmod.Role = switch (k) {
                .berserker => .berserker,
                .priest => .priest,
                else => .slinger,
            };
            cs.band.n = 1;
            cs.band.live()[0] = koboldmod.Kobold.spawnAs(role, mathx.zero3, 0, 1.0, seed);
            cs.band.draw(scene);
        },
        .brood_mother, .broodling, .brood_sac => {
            const role: broodmod.Role = if (k == .broodling) .broodling else .mother;
            cs.brood.n = 1;
            cs.brood.live()[0] = broodmod.Spider.spawnAs(role, mathx.zero3, 0, 1.0, seed);
            cs.brood.draw(scene);
        },
        .shieldman, .greatsword => {
            cs.muster.n = 1;
            cs.muster.live()[0] = warriormod.Warrior.spawnAs(if (k == .shieldman) .shieldman else .greatsword, mathx.zero3, 0, 1.0, seed);
            cs.muster.draw(scene);
        },
        .fish_spearman, .fish_netter, .fish_shaman => {
            cs.shoal.n = 1;
            cs.shoal.live()[0] = fishmod.Fishman.spawnAs(fishmod.roleOf(k).?, mathx.zero3, 0, 1.0, seed);
            cs.shoal.draw(scene);
        },
        .blinkbat => {
            cs.roost.n = 1;
            cs.roost.live()[0] = batmod.Bat.spawn(mathx.zero3, 0, 1.0, seed);
            cs.roost.draw(scene);
        },
        .owlbear => {
            cs.perch.n = 1;
            cs.perch.live()[0] = owlbearmod.Owlbear.spawn(mathx.zero3, 0, 1.0, seed);
            cs.perch.draw(scene);
        },
        .salt_husk => {
            cs.pan.n = 1;
            cs.pan.live()[0] = huskmod.Husk.spawn(mathx.zero3, 0, 1.0, seed);
            cs.pan.draw(scene);
        },
        .birchwight => {
            cs.stand.n = 1;
            cs.stand.live()[0] = birchmod.Wight.spawn(mathx.zero3, 0, 1.0, seed);
            cs.stand.draw(scene);
        },
        .rotgorger => {
            cs.gorge.n = 1;
            cs.gorge.live()[0] = gorgermod.Gorger.spawn(mathx.zero3, 0, 1.0, seed);
            cs.gorge.draw(scene);
        },
        .cinder_wake => {
            cs.scorch.n = 1;
            cs.scorch.live()[0] = cindermod.Cinder.spawn(mathx.zero3, 0, 1.0, seed);
            cs.scorch.draw(scene);
        },
        .slumber_bloom => {
            cs.bed.n = 1;
            cs.bed.live()[0] = bloommod.Bloom.spawn(mathx.zero3, 0, 1.0, seed);
            cs.bed.live()[0].debugWake();
            cs.bed.live()[0].open = 1;
            cs.bed.live()[0].pose();
            cs.bed.draw(scene);
        },
        .shade, .mourner => {
            cs.haunt.n = 1;
            cs.haunt.live()[0] = shademod.Shade.spawnAs(if (k == .mourner) .mourner else .shade, mathx.zero3, 0, 1.0, seed);
            cs.haunt.draw(scene);
        },
        .leechfly => {
            cs.swarm.n = 1;
            cs.swarm.live()[0] = leechmod.Leechfly.spawn(mathx.zero3, 0, 1.0, seed);
            cs.swarm.draw(scene);
        },
        .rooted => {
            cs.grove.n = 1;
            var t = rootedmod.Rooted.spawn(mathx.zero3, 0, 1.0, seed);
            t.open = 1;
            t.eyes = 1;
            t.pose();
            cs.grove.live()[0] = t;
            cs.grove.draw(scene);
        },
        .shroom => {
            cs.cluster.n = 1;
            cs.cluster.live()[0] = shroommod.Shroom.spawn(mathx.zero3, 0, 1.0, seed);
            cs.cluster.draw(scene);
        },
        .bone_knight => {
            cs.vigil.n = 1;
            cs.vigil.live()[0] = knightmod.Knight.spawn(mathx.zero3, 0, 1.0, seed);
            cs.vigil.draw(scene);
        },
        .delver => {
            cs.warrens.n = 1;
            cs.warrens.live()[0] = delvermod.Delver.spawn(mathx.zero3, 0, 1.0, seed);
            cs.warrens.draw(scene);
        },
        .necromancer => {
            cs.rite.n = 1;
            cs.rite.live()[0] = necromod.Necro.spawn(mathx.zero3, 0, 1.0, seed);
            cs.rite.draw(scene);
        },
        .fungal_deer => {
            cs.herd.n = 1;
            cs.herd.live()[0] = deermod.Deer.spawn(mathx.zero3, 0, 1.0, seed);
            cs.herd.live()[0].stageGather(1.0);
            cs.herd.draw(scene);
        },
        .spore_golem => {
            cs.host.n = 1;
            cs.host.live()[0] = golemmod.Golem.spawn(mathx.zero3, 0, 1.0, seed);
            cs.host.draw(scene);
        },
        .mushroom_mage => {
            cs.ring.n = 1;
            cs.ring.live()[0] = magemod.Mage.spawn(mathx.zero3, 0, 1.0, seed);
            cs.ring.live()[0].stageGather(1.0);
            cs.ring.draw(scene);
        },
        .fen_lurker => {
            cs.marsh.n = 1;
            cs.marsh.live()[0] = fenmod.Lurker.spawn(mathx.zero3, 0, 1.0, seed);
            cs.marsh.live()[0].stageGather(1.0);
            cs.marsh.draw(scene);
        },
        .bone_skitterer => {
            cs.clatter.n = 1;
            cs.clatter.live()[0] = skittermod.Skitterer.spawn(mathx.zero3, 0, 1.0, seed);
            cs.clatter.live()[0].stageGather(0.85);
            cs.clatter.draw(scene);
        },
        .ancient_priest => {
            cs.crypt.n = 1;
            cs.crypt.live()[0] = priestmod.Ancient.spawn(mathx.zero3, 0, 1.0, seed);
            cs.crypt.live()[0].stageGather(1.0);
            cs.crypt.draw(scene);
        },
        .tolling_hollow => {
            cs.belfry.n = 1;
            cs.belfry.live()[0] = hollowmod.Hollow.spawn(mathx.zero3, 0, 1.0, seed);
            cs.belfry.live()[0].stageGather(0.9);
            cs.belfry.draw(scene);
        },
        .fungal_swordsman => {
            cs.vanguard.n = 1;
            cs.vanguard.live()[0] = duomod.Swordsman.spawn(mathx.zero3, 0, 1.0, seed);
            cs.vanguard.draw(scene);
        },
        .fungal_magus => {
            cs.conclave.n = 1;
            cs.conclave.live()[0] = duomod.Magus.spawn(mathx.zero3, 0, 1.0, seed);
            cs.conclave.draw(scene);
        },
    }
}

fn renderChar(rt: rl.RenderTexture2D, env: *envmod.Env, scene: *gfx.Scene, k: wf.FoeKind, pose: Pose) void {
    const cs = ensureChars(scene);
    const dims = charDims(k);
    const aspect = rtAspect(rt);
    openStage(rt, env, scene, fitCam(dims.top, dims.bound, pose, aspect), aspect);
    drawChar(cs, k, scene);
    closeStage();
}


fn iconLabel(i: usize) [:0]const u8 {
    if (i < GLYPH_N) return @tagName(@as(icons.Icon, @enumFromInt(i)));
    return item.displayName(@enumFromInt(i - GLYPH_N));
}

fn drawIconAt(i: usize, cx: f32, cy: f32, size: f32) void {
    if (i < GLYPH_N) {
        icons.draw(@enumFromInt(i), cx, cy, size, ui.VALUE);
    } else {
        itemart.draw(@enumFromInt(i - GLYPH_N), cx, cy, size);
    }
}

fn blit(rt: rl.RenderTexture2D, dst: rl.Rectangle) void {
    const w: f32 = @floatFromInt(rt.texture.width);
    const h: f32 = @floatFromInt(rt.texture.height);
    rl.drawTexturePro(
        rt.texture,
        .{ .x = 0, .y = 0, .width = w, .height = -h },
        dst,
        .{ .x = 0, .y = 0 },
        0,
        rl.Color.white,
    );
}


const COLS: i32 = 4;
const ROWS: i32 = 3;
const CELL_GAP: i32 = 10;
const LABEL_H: i32 = 18;
const HEADER: i32 = 78;
const FOOTER: i32 = 44;
const FOOT_DROP: i32 = 34;

fn perPage() i32 {
    return COLS * ROWS;
}

fn cellW() i32 {
    return THUMB_W + CELL_GAP;
}

fn cellH() i32 {
    return THUMB_H + LABEL_H + CELL_GAP;
}

fn modalW() i32 {
    return COLS * cellW() + CELL_GAP + 24;
}

fn modalH() i32 {
    return HEADER + ROWS * cellH() + FOOTER;
}

const GRID_INSET: i32 = 16;

fn gridCell(box: ui.ModalBox, slot: i32) rl.Rectangle {
    return ui.rect(
        box.x + GRID_INSET + @mod(slot, COLS) * cellW(),
        box.y + HEADER + @divTrunc(slot, COLS) * cellH(),
        THUMB_W,
        THUMB_H,
    );
}

fn pageCount(n: usize) i32 {
    const total: i32 = @intCast(n);
    return @max(1, @divTrunc(total + perPage() - 1, perPage()));
}

fn lineH() i32 {
    return ui.ROW_H;
}

const clampI = mathx.clampI;

fn modeTabs(st: *State, ctx: *ui.Ctx, x0: i32, y: i32) struct { changed: bool, x: i32 } {
    var tx = x0;
    var changed = false;
    inline for (@typeInfo(Mode).@"enum".fields) |f| {
        const m: Mode = @enumFromInt(f.value);
        var usedW: i32 = 0;
        if (ui.chip(ctx, tx, y, m.label(), st.mode == m, &usedW, "Which bench you are on - props, creatures, the icon sheet or the element FX") and st.mode != m) {
            st.mode = m;
            st.page = 0;
            st.grabbed = null;
            st.open = null;
            st.openIcon = null;
            st.openChar = null;
            changed = true;
        }
        tx += usedW;
    }
    return .{ .changed = changed, .x = tx + 18 };
}

fn gallery(st: *State, env: *envmod.Env, scene: *gfx.Scene, ctx: *ui.Ctx) bool {
    const list = st.shelf.kinds();
    const pages = pageCount(list.len);
    st.page = clampI(st.page, 0, pages - 1);
    const box = ui.beginModal(ctx, modalW(), modalH(), "Object viewer");

    const ty = box.y + 44;
    const tabs = modeTabs(st, ctx, box.x + 16, ty);
    if (tabs.changed) return true;
    var tx = tabs.x;
    inline for (@typeInfo(Shelf).@"enum".fields) |f| {
        const s: Shelf = @enumFromInt(f.value);
        var usedW: i32 = 0;
        if (ui.chip(ctx, tx, ty, s.label(), st.shelf == s, &usedW, "Narrow the grid to this family") and st.shelf != s) {
            st.shelf = s;
            st.page = 0;
            st.grabbed = null;
        }
        tx += usedW;
    }

    const start: usize = @intCast(st.page * perPage());
    const end = @min(start + @as(usize, @intCast(perPage())), list.len);

    var hover: ?usize = null;
    var hoverRect: rl.Rectangle = undefined;
    var i = start;
    while (i < end) : (i += 1) {
        const r = gridCell(box, @intCast(i - start));
        if (rl.checkCollisionPointRec(ctx.mouse, r)) {
            hover = i;
            hoverRect = r;
        }
    }

    if (ctx.wheel != 0) {
        if (hover) |h| {
            const p = st.poseOf(list[h]);
            p.zoom = mathx.clampF(p.zoom * (1.0 + ZOOM_RATE * ctx.wheel), MIN_ZOOM, MAX_ZOOM);
        } else {
            st.page = clampI(st.page + (if (ctx.wheel < 0) @as(i32, 1) else -1), 0, pages - 1);
        }
    }

    if (ctx.pressed) {
        st.grabbed = hover;
        st.travel = 0;
    }
    if (st.grabbed) |g| {
        if (g >= list.len) {
            st.grabbed = null;
        } else if (rl.isMouseButtonDown(.left)) {
            const d = rl.getMouseDelta();
            st.travel += @abs(d.x) + @abs(d.y);
            if (st.travel > CLICK_SLOP) {
                const p = st.poseOf(list[g]);
                p.yaw += d.x * ROT_RATE;
                p.pitch = mathx.clampF(p.pitch - d.y * ROT_RATE, MIN_PITCH, MAX_PITCH);
            }
        } else {
            if (st.travel <= CLICK_SLOP) st.open = list[g];
            st.grabbed = null;
        }
    }

    i = start;
    while (i < end) : (i += 1) {
        const kind = list[i];
        const r = gridCell(box, @intCast(i - start));
        render(target(&thumbRT, THUMB_W, THUMB_H), env, scene, kind, st.poseOf(kind).*);
        blit(thumbRT.?, r);
        const on = (hover != null and hover.? == i) or (st.grabbed != null and st.grabbed.? == i);
        rl.drawRectangleLinesEx(r, 1, ui.alpha(if (on) ui.HOT else ui.TRIM, if (on) 220 else 70));
        const name = props.displayName(kind);
        const nw = hud.monoW(name, hud.MONO);
        hud.mono(
            name,
            @as(i32, @intFromFloat(r.x)) + @divTrunc(THUMB_W - nw, 2),
            @as(i32, @intFromFloat(r.y + r.height)) + 3,
            hud.MONO,
            if (on) ui.HOT else ui.LABEL,
        );
    }

    const by = box.y + box.h - FOOT_DROP;
    if (ui.button(ctx, ui.rect(box.x + 16, by, 44, 24), "<", hud.MONO, false, "The page before this one")) st.page = @max(0, st.page - 1);
    if (ui.button(ctx, ui.rect(box.x + 64, by, 44, 24), ">", hud.MONO, false, "The page after this one")) st.page = @min(pages - 1, st.page + 1);
    var buf: [96]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "page {d}/{d}   {d} objects   drag spins, wheel zooms, click opens", .{ st.page + 1, pages, list.len }) catch "";
    hud.mono(s, box.x + 120, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + box.w - 96, by, 80, 24), "Close", hud.MONO, false, "Shut the viewer and go back to the editor (Esc)")) return false;
    return true;
}


const BIG_PAD: i32 = 16;
const INFO_W: i32 = 300;

fn spinView(st: *State, ctx: *ui.Ctx, p: *Pose, viewR: rl.Rectangle) void {
    const overView = rl.checkCollisionPointRec(ctx.mouse, viewR);
    if (overView and ctx.wheel != 0) p.zoom = mathx.clampF(p.zoom * (1.0 + ZOOM_RATE * ctx.wheel), MIN_ZOOM, MAX_ZOOM);
    if (ctx.pressed and overView) st.grabbed = 0;
    if (st.grabbed == null) return;
    if (!rl.isMouseButtonDown(.left)) {
        st.grabbed = null;
        return;
    }
    const d = rl.getMouseDelta();
    p.yaw += d.x * ROT_RATE;
    p.pitch = mathx.clampF(p.pitch - d.y * ROT_RATE, MIN_PITCH, MAX_PITCH);
}

fn big(st: *State, env: *envmod.Env, scene: *gfx.Scene, ctx: *ui.Ctx, kind: Kind) bool {
    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    const w = @min(sw - 60, BIG_W + INFO_W + 3 * BIG_PAD);
    const h = @min(sh - 60, BIG_H + 96);
    const box = ui.beginModal(ctx, w, h, props.displayName(kind));

    const viewR = ui.rect(
        box.x + BIG_PAD,
        box.y + 46,
        w - INFO_W - 3 * BIG_PAD,
        h - 46 - 44,
    );
    const p = st.poseOf(kind);

    spinView(st, ctx, p, viewR);

    render(target(&bigRT, BIG_W, BIG_H), env, scene, kind, p.*);
    blit(bigRT.?, viewR);
    rl.drawRectangleLinesEx(viewR, 1, ui.alpha(ui.TRIM, 110));

    const nfo = props.info(kind);
    const x = box.x + w - INFO_W - BIG_PAD;
    var y = box.y + 52;
    const line = lineH();
    var buf: [64]u8 = undefined;
    hud.mono(props.group(kind).label(), x, y, hud.MONO, ui.alpha(ui.TRIM, 230));
    y += line + 4;
    const rows = .{
        .{ "bound", nfo.bound },
        .{ "top", nfo.top },
        .{ "view", nfo.view },
    };
    inline for (rows) |row| {
        const s = std.fmt.bufPrintZ(&buf, "{s: <7}{d: >7.2}", .{ row[0], row[1] }) catch "";
        hud.mono(s, x, y, hud.MONO, ui.VALUE);
        y += line;
    }
    const flags = std.fmt.bufPrintZ(&buf, "{s}{s}{s}", .{
        if (nfo.flora) "flora " else "",
        if (nfo.casts) "casts " else "",
        if (nfo.light != null) "lit" else "",
    }) catch "";
    hud.mono(flags, x, y, hud.MONO, ui.alpha(ui.VALUE, 220));
    y += line;
    const solids = std.fmt.bufPrintZ(&buf, "{d} collider{s}, {s}", .{
        nfo.parts.len,
        if (nfo.parts.len == 1) "" else "s",
        @tagName(nfo.surf),
    }) catch "";
    hud.mono(solids, x, y, hud.MONO, ui.alpha(ui.VALUE, 220));
    y += line + 6;
    const zoomS = std.fmt.bufPrintZ(&buf, "zoom {d: >5.2}x", .{p.zoom}) catch "";
    hud.mono(zoomS, x, y, hud.MONO, ui.alpha(ui.LABEL, 210));
    y += line;
    hud.mono("drag spins", x, y, hud.MONO, ui.alpha(ui.LABEL, 170));
    y += line;
    hud.mono("wheel zooms", x, y, hud.MONO, ui.alpha(ui.LABEL, 170));

    const list = st.shelf.kinds();
    var at: usize = 0;
    for (list, 0..) |k, idx| {
        if (k == kind) at = idx;
    }
    const by = box.y + box.h - FOOT_DROP;
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD, by, 44, 24), "<", hud.MONO, false, "The kind before this one, wrapping round")) {
        st.open = list[if (at == 0) list.len - 1 else at - 1];
    }
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD + 48, by, 44, 24), ">", hud.MONO, false, "The kind after this one, wrapping round")) {
        st.open = list[if (at + 1 >= list.len) 0 else at + 1];
    }
    var cb: [64]u8 = undefined;
    const count = std.fmt.bufPrintZ(&cb, "{d}/{d} in {s}", .{ at + 1, list.len, st.shelf.label() }) catch "";
    hud.mono(count, box.x + BIG_PAD + 104, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + box.w - 176, by, 74, 24), "Reset", hud.MONO, false, "Back to the house angle and distance")) p.* = .{};
    if (ui.button(ctx, ui.rect(box.x + box.w - 96, by, 80, 24), "Back", hud.MONO, false, "Back to the grid")) return false;
    return true;
}


fn galleryChars(st: *State, env: *envmod.Env, scene: *gfx.Scene, ctx: *ui.Ctx) bool {
    const pages = pageCount(CHAR_N);
    st.page = clampI(st.page, 0, pages - 1);
    const box = ui.beginModal(ctx, modalW(), modalH(), "Object viewer");
    if (modeTabs(st, ctx, box.x + 16, box.y + 44).changed) return true;

    const start: usize = @intCast(st.page * perPage());
    const end = @min(start + @as(usize, @intCast(perPage())), CHAR_N);

    var hover: ?usize = null;
    var i = start;
    while (i < end) : (i += 1) {
        const r = gridCell(box, @intCast(i - start));
        if (rl.checkCollisionPointRec(ctx.mouse, r)) hover = i;
    }
    if (ctx.wheel != 0) {
        if (hover) |h| {
            const p = &st.charPose[h];
            p.zoom = mathx.clampF(p.zoom * (1.0 + ZOOM_RATE * ctx.wheel), MIN_ZOOM, MAX_ZOOM);
        } else {
            st.page = clampI(st.page + (if (ctx.wheel < 0) @as(i32, 1) else -1), 0, pages - 1);
        }
    }
    if (ctx.pressed) {
        st.grabbed = hover;
        st.travel = 0;
    }
    if (st.grabbed) |g| {
        if (g >= CHAR_N) {
            st.grabbed = null;
        } else if (rl.isMouseButtonDown(.left)) {
            const d = rl.getMouseDelta();
            st.travel += @abs(d.x) + @abs(d.y);
            if (st.travel > CLICK_SLOP) {
                const p = &st.charPose[g];
                p.yaw += d.x * ROT_RATE;
                p.pitch = mathx.clampF(p.pitch - d.y * ROT_RATE, MIN_PITCH, MAX_PITCH);
            }
        } else {
            if (st.travel <= CLICK_SLOP) st.openChar = g;
            st.grabbed = null;
        }
    }

    i = start;
    while (i < end) : (i += 1) {
        const k = CHAR_KINDS[i];
        const r = gridCell(box, @intCast(i - start));
        renderChar(target(&thumbRT, THUMB_W, THUMB_H), env, scene, k, st.charPose[i]);
        blit(thumbRT.?, r);
        const on = (hover != null and hover.? == i) or (st.grabbed != null and st.grabbed.? == i);
        rl.drawRectangleLinesEx(r, 1, ui.alpha(if (on) ui.HOT else ui.TRIM, if (on) 220 else 70));
        const name = wf.foeName(k);
        const nw = hud.monoW(name, hud.MONO);
        hud.mono(name, @as(i32, @intFromFloat(r.x)) + @divTrunc(THUMB_W - nw, 2), @as(i32, @intFromFloat(r.y + r.height)) + 3, hud.MONO, if (on) ui.HOT else ui.LABEL);
    }

    const by = box.y + box.h - FOOT_DROP;
    if (ui.button(ctx, ui.rect(box.x + 16, by, 44, 24), "<", hud.MONO, false, "The page before this one")) st.page = @max(0, st.page - 1);
    if (ui.button(ctx, ui.rect(box.x + 64, by, 44, 24), ">", hud.MONO, false, "The page after this one")) st.page = @min(pages - 1, st.page + 1);
    var buf: [96]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "page {d}/{d}   {d} characters   drag spins, wheel zooms, click opens", .{ st.page + 1, pages, CHAR_N }) catch "";
    hud.mono(s, box.x + 120, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + box.w - 96, by, 80, 24), "Close", hud.MONO, false, "Shut the viewer and go back to the editor (Esc)")) return false;
    return true;
}

fn bigChar(st: *State, env: *envmod.Env, scene: *gfx.Scene, ctx: *ui.Ctx, at: usize) bool {
    const k = CHAR_KINDS[at];
    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    const w = @min(sw - 60, BIG_W + INFO_W + 3 * BIG_PAD);
    const h = @min(sh - 60, BIG_H + 96);
    const box = ui.beginModal(ctx, w, h, wf.foeName(k));
    const viewR = ui.rect(box.x + BIG_PAD, box.y + 46, w - INFO_W - 3 * BIG_PAD, h - 46 - 44);
    const p = &st.charPose[at];

    spinView(st, ctx, p, viewR);

    renderChar(target(&bigRT, BIG_W, BIG_H), env, scene, k, p.*);
    blit(bigRT.?, viewR);
    rl.drawRectangleLinesEx(viewR, 1, ui.alpha(ui.TRIM, 110));

    const dims = charDims(k);
    const x = box.x + w - INFO_W - BIG_PAD;
    var y = box.y + 52;
    const line = lineH();
    var buf: [64]u8 = undefined;
    hud.mono("character", x, y, hud.MONO, ui.alpha(ui.TRIM, 230));
    y += line + 4;
    inline for (.{ .{ "top", dims.top }, .{ "bound", dims.bound } }) |row| {
        const s = std.fmt.bufPrintZ(&buf, "{s: <7}{d: >7.2}", .{ row[0], row[1] }) catch "";
        hud.mono(s, x, y, hud.MONO, ui.VALUE);
        y += line;
    }
    y += 8;
    y = tuneui.faceSheet(ctx, x, y, INFO_W, .foe, @intFromEnum(k), box.y + h - FOOT_DROP - 24);
    y += 2;
    hud.mono("drag spins, wheel zooms", x, y, hud.MONO, ui.alpha(ui.LABEL, 170));

    const by = box.y + box.h - FOOT_DROP;
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD, by, 44, 24), "<", hud.MONO, false, "The creature before this one, wrapping round")) st.openChar = if (at == 0) CHAR_N - 1 else at - 1;
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD + 48, by, 44, 24), ">", hud.MONO, false, "The creature after this one, wrapping round")) st.openChar = if (at + 1 >= CHAR_N) 0 else at + 1;
    var cb: [64]u8 = undefined;
    const count = std.fmt.bufPrintZ(&cb, "{d}/{d} characters", .{ at + 1, CHAR_N }) catch "";
    hud.mono(count, box.x + BIG_PAD + 104, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + box.w - 176, by, 74, 24), "Reset", hud.MONO, false, "Back to the house angle and distance")) p.* = .{};
    if (ui.button(ctx, ui.rect(box.x + box.w - 96, by, 80, 24), "Back", hud.MONO, false, "Back to the grid")) return false;
    return true;
}

fn galleryIcons(st: *State, ctx: *ui.Ctx) bool {
    const pages = pageCount(ICONS_TOTAL);
    st.page = clampI(st.page, 0, pages - 1);
    const box = ui.beginModal(ctx, modalW(), modalH(), "Object viewer");
    if (modeTabs(st, ctx, box.x + 16, box.y + 44).changed) return true;

    const start: usize = @intCast(st.page * perPage());
    const end = @min(start + @as(usize, @intCast(perPage())), ICONS_TOTAL);
    var hover: ?usize = null;
    var i = start;
    while (i < end) : (i += 1) {
        const r = gridCell(box, @intCast(i - start));
        const on = rl.checkCollisionPointRec(ctx.mouse, r);
        if (on) hover = i;
        rl.drawRectangleRec(r, BACKDROP);
        drawIconAt(i, r.x + r.width * 0.5, r.y + r.height * 0.5, @min(r.width, r.height) * 0.62);
        rl.drawRectangleLinesEx(r, 1, ui.alpha(if (on) ui.HOT else ui.TRIM, if (on) 220 else 70));
        const name = iconLabel(i);
        const nw = hud.monoW(name, hud.MONO);
        hud.mono(name, @as(i32, @intFromFloat(r.x)) + @divTrunc(THUMB_W - nw, 2), @as(i32, @intFromFloat(r.y + r.height)) + 3, hud.MONO, if (on) ui.HOT else ui.LABEL);
    }
    if (ctx.wheel != 0 and hover == null) st.page = clampI(st.page + (if (ctx.wheel < 0) @as(i32, 1) else -1), 0, pages - 1);
    if (ctx.pressed and hover != null) st.openIcon = hover;

    const by = box.y + box.h - FOOT_DROP;
    if (ui.button(ctx, ui.rect(box.x + 16, by, 44, 24), "<", hud.MONO, false, "The page before this one")) st.page = @max(0, st.page - 1);
    if (ui.button(ctx, ui.rect(box.x + 64, by, 44, 24), ">", hud.MONO, false, "The page after this one")) st.page = @min(pages - 1, st.page + 1);
    var buf: [96]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "page {d}/{d}   {d} glyphs + {d} pictures   click enlarges", .{ st.page + 1, pages, GLYPH_N, PICT_N }) catch "";
    hud.mono(s, box.x + 120, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + box.w - 96, by, 80, 24), "Close", hud.MONO, false, "Shut the viewer and go back to the editor (Esc)")) return false;
    return true;
}

fn bigIcon(st: *State, ctx: *ui.Ctx, at: usize) bool {
    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    // **A PICTURE OF A THING IS ALSO THE THING'S SHEET.** An editor glyph has no numbers behind it and keeps the
    const kind: ?item.Kind = if (at >= GLYPH_N) @enumFromInt(at - GLYPH_N) else null;
    const wide = kind != null;
    const w = @min(sw - 60, @as(i32, if (wide) 900 else 720));
    const h = @min(sh - 60, 640);
    const box = ui.beginModal(ctx, w, h, iconLabel(at));
    const artW = if (wide) w - INFO_W - 3 * BIG_PAD else w;
    const cx = @as(f32, @floatFromInt(box.x)) + @as(f32, @floatFromInt(artW)) * 0.5;
    const cy = @as(f32, @floatFromInt(box.y)) + @as(f32, @floatFromInt(h)) * 0.5;
    drawIconAt(at, cx, cy, @as(f32, @floatFromInt(@min(artW, h))) * 0.62);
    if (kind) |k| {
        const ix = box.x + w - INFO_W - BIG_PAD;
        var iy = box.y + 52;
        hud.mono(item.class(k).label(), ix, iy, hud.MONO, ui.alpha(ui.TRIM, 230));
        iy += hud.monoLineH(hud.MONO) + 6;
        _ = tuneui.faceSheet(ctx, ix, iy, INFO_W, .item, @intFromEnum(k), box.y + h - 40);
    }

    const by = box.y + box.h - FOOT_DROP;
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD, by, 44, 24), "<", hud.MONO, false, "The glyph before this one, wrapping round")) st.openIcon = if (at == 0) ICONS_TOTAL - 1 else at - 1;
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD + 48, by, 44, 24), ">", hud.MONO, false, "The glyph after this one, wrapping round")) st.openIcon = if (at + 1 >= ICONS_TOTAL) 0 else at + 1;
    if (ui.button(ctx, ui.rect(box.x + box.w - 96, by, 80, 24), "Back", hud.MONO, false, "Back to the grid")) return false;
    return true;
}

fn benchAt(v: Verb) rl.Vector3 {
    return if (v == .pour) v3(0, 1.05, combat.RIME_REACH * 0.5) else BENCH_AT;
}

fn benchRng(st: *const State) mathx.Rng {
    return mathx.Rng.init(@as(u64, st.fxHead) *% 2654435761 +% 0x8BEF);
}

fn benchFire(st: *State) void {
    var rng = benchRng(st);
    switch (st.verb) {
        .gather => elemfx.gather(&st.fx, &st.fxHead, &rng, benchAt(.gather), st.elem, 26, 0.55, 1.0),
        .burst => elemfx.burst(&st.fx, &st.fxHead, &rng, benchAt(.burst), BENCH_DIR, st.elem, 24, 1.0),
        .pour => {},
    }
}

fn benchClear(st: *State) void {
    st.fx = [_]foemod.Particle{.{}} ** BENCH_FX_N;
    st.fxHead = 0;
    st.fxT = 0;
    st.fxAcc = 0;
}

fn benchStep(st: *State, dt: f32) void {
    st.fxT += dt;
    if (st.verb == .pour) {
        var rng = benchRng(st);
        var n = foemod.emitTicks(&st.fxAcc, dt, elemfx.POUR_RATE, BENCH_POUR_CAP);
        while (n > 0) : (n -= 1) {
            elemfx.pour(&st.fx, &st.fxHead, &rng, benchAt(.pour), BENCH_DIR, st.elem, 1, mathx.radians(combat.RIME_ARC), combat.RIME_REACH, 1.0);
        }
    } else if (st.fxT >= st.verb.loop()) {
        st.fxT = 0;
        benchFire(st);
    }
    foemod.tickParticles(&st.fx, dt, 0);
}

fn renderBench(rt: rl.RenderTexture2D, env: *envmod.Env, scene: *gfx.Scene, st: *const State) void {
    const aspect = rtAspect(rt);
    const wide = st.verb == .pour;
    openStage(rt, env, scene, fitCam(if (wide) 2.4 else 1.7, if (wide) combat.RIME_REACH * 0.62 else 1.1, st.fxPose, aspect), aspect);
    foemod.drawParticles(&st.fx);
    closeStage();
}


fn volReset(st: *State) void {
    st.volT = 0;
    st.volCloud = .{ .pos = mathx.zero3, .live = true, .fxRng = foemod.fxStream(1.0, 977.0, 0xC10D) };
    st.volPool = broodmod.Pool.splash(mathx.zero3, 0.5);
    st.volGas = .{ .pos = mathx.zero3, .scale = 1.0, .live = true, .fxRng = foemod.fxStream(2.0, 641.0, 0x6A50) };
}

fn volStep(st: *State, dt: f32) void {
    st.volT += dt;
    if (st.volT >= st.vol.loop()) volReset(st);
    switch (st.vol) {
        .spore_cloud => st.volCloud.update(dt),
        .acid_pool => st.volPool.update(dt),
        .knight_gas => st.volGas.update(dt),
    }
}

fn volRadius(st: *const State) f32 {
    return switch (st.vol) {
        .spore_cloud => st.volCloud.radius(),
        .acid_pool => st.volPool.radius(),
        .knight_gas => st.volGas.radius(),
    };
}

fn volDrawFx(st: *const State) void {
    switch (st.vol) {
        .spore_cloud => st.volCloud.drawFx(),
        .acid_pool => st.volPool.drawFx(),
        .knight_gas => st.volGas.drawFx(),
    }
}

fn renderVolume(st: *State, rt: rl.RenderTexture2D, env: *envmod.Env, scene: *gfx.Scene) void {
    const aspect = rtAspect(rt);
    // Framed on the volume's OWN reach, not on a fixed box: a 1.55 m pool and a 1.9 m cloud want different cameras, and the whole point of the bench is comparing what they actually cover.
    const reach = mathx.maxF(volRadius(st), 0.5) * 2.2;
    openStage(rt, env, scene, fitCam(reach * 0.5, reach, st.volPose, aspect), aspect);
    ringOnGround(volRadius(st), ui.LIVE);
    volDrawFx(st);
    closeStage();
}

fn ringOnGround(r: f32, col: rl.Color) void {
    const SEG = 48;
    var prev = mathx.v3(r, 0.02, 0);
    var i: usize = 1;
    while (i <= SEG) : (i += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / SEG;
        const p = mathx.v3(mathx.cosf(a) * r, 0.02, mathx.sinf(a) * r);
        rl.drawLine3D(prev, p, col);
        prev = p;
    }
}

fn volumePanel(st: *State, env: *envmod.Env, scene: *gfx.Scene, ctx: *ui.Ctx) bool {
    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    const w = @min(sw - 60, BIG_W + INFO_W + 3 * BIG_PAD);
    const h = @min(sh - 60, BIG_H + 130);
    const box = ui.beginModal(ctx, w, h, "Gas & AOE bench");
    if (modeTabs(st, ctx, box.x + 16, box.y + 44).changed) return true;

    var tx = box.x + 16;
    const vy = box.y + 78;
    inline for (@typeInfo(Volume).@"enum".fields) |f| {
        const v: Volume = @enumFromInt(f.value);
        var usedW: i32 = 0;
        if (ui.chip(ctx, tx, vy, v.label(), st.vol == v, &usedW, "How much of the effect to pour - the same shape the game fires it at") and st.vol != v) {
            st.vol = v;
            volReset(st);
        }
        tx += usedW;
    }

    volStep(st, rl.getFrameTime());
    const viewR = ui.rect(box.x + BIG_PAD, vy + ui.ROW_H + 10, w - INFO_W - 3 * BIG_PAD, h - (vy - box.y) - ui.ROW_H - 10 - 44);
    spinView(st, ctx, &st.volPose, viewR);
    renderVolume(st, target(&bigRT, BIG_W, BIG_H), env, scene);
    blit(bigRT.?, viewR);
    rl.drawRectangleLinesEx(viewR, 1, ui.alpha(ui.TRIM, 110));

    const ix = box.x + w - INFO_W - BIG_PAD;
    var iy: i32 = @intFromFloat(viewR.y);
    var buf: [3 * 96]u8 = undefined;
    const rows = volFacts(st, &buf);
    hud.mono(rows.a, ix, iy, hud.MONO, ui.VALUE);
    iy += ui.ROW_H;
    hud.mono(rows.b, ix, iy, hud.MONO, ui.LABEL);
    iy += ui.ROW_H;
    hud.mono(rows.c, ix, iy, hud.MONO, ui.LABEL);
    iy += ui.ROW_H + 6;
    var tbuf: [40]u8 = undefined;
    const now = std.fmt.bufPrintZ(&tbuf, "t {d:.2} / {d:.2} s   r {d:.2} m", .{ st.volT, st.vol.loop(), volRadius(st) }) catch "";
    hud.mono(now, ix, iy, hud.MONO, ui.LIVE);
    return true;
}

const VolFacts = struct { a: [:0]const u8, b: [:0]const u8, c: [:0]const u8 };

fn volFacts(st: *const State, buf: []u8) VolFacts {
    const third = buf.len / 3;
    const b1 = buf[third .. third * 2];
    const b2 = buf[third * 2 ..];
    return switch (st.vol) {
        .spore_cloud => .{
            .a = "POISON - builds while you stand in it",
            .b = std.fmt.bufPrintZ(b1, "r {d:.2} m   life {d:.2} s   build {d:.0}/s", .{ shroommod.CLOUD_R, shroommod.CLOUD_LIFE, shroommod.SPORE_BUILD }) catch "",
            .c = std.fmt.bufPrintZ(b2, "Entry costs {d:.2} s of build up front", .{foemod.ENTRY_BOLUS}) catch "",
        },
        .acid_pool => .{
            .a = "ACID - spreads, then thins",
            .b = std.fmt.bufPrintZ(b1, "r {d:.2} m   life {d:.2} s   build {d:.0}/s", .{ broodmod.ACID_R, broodmod.ACID_LIFE, broodmod.ACID_BUILD }) catch "",
            .c = std.fmt.bufPrintZ(b2, "Entry costs {d:.2} s of build up front", .{foemod.ENTRY_BOLUS}) catch "",
        },
        .knight_gas => .{
            .a = "CHAOS - dosed on a clock, not built",
            .b = std.fmt.bufPrintZ(b1, "r {d:.2} m   life {d:.2} s   dose every {d:.2} s", .{ knightmod.GAS_R, knightmod.GAS_LIFE, knightmod.GAS_DOSE_EVERY }) catch "",
            .c = "First frame in is already due",
        },
    };
}

fn benchPanel(st: *State, env: *envmod.Env, scene: *gfx.Scene, ctx: *ui.Ctx) bool {
    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    const w = @min(sw - 60, BIG_W + INFO_W + 3 * BIG_PAD);
    const h = @min(sh - 60, BIG_H + 130);
    const box = ui.beginModal(ctx, w, h, "Effects bench");
    if (modeTabs(st, ctx, box.x + 16, box.y + 44).changed) return true;

    var tx = box.x + 16;
    const ey = box.y + 78;
    inline for (@typeInfo(combat.Elem).@"enum".fields) |f| {
        const e: combat.Elem = @enumFromInt(f.value);
        var usedW: i32 = 0;
        if (ui.chip(ctx, tx, ey, combat.elemName(e), st.elem == e, &usedW, "Which element to bench. Each has its own signature: fire rises, cold falls and lies about, lightning does not travel, chaos goes inward") and st.elem != e) {
            st.elem = e;
            benchClear(st);
        }
        tx += usedW;
    }
    tx = box.x + 16;
    const vy = ey + ui.ROW_H + 8;
    inline for (@typeInfo(Verb).@"enum".fields) |f| {
        const v: Verb = @enumFromInt(f.value);
        var usedW: i32 = 0;
        if (ui.chip(ctx, tx, vy, v.label(), st.verb == v, &usedW, "Which shape to fire - gather, burst or pour. Each reads differently per element") and st.verb != v) {
            st.verb = v;
            benchClear(st);
        }
        tx += usedW;
    }

    const viewR = ui.rect(box.x + BIG_PAD, vy + ui.ROW_H + 10, w - INFO_W - 3 * BIG_PAD, h - (vy - box.y) - ui.ROW_H - 56);
    spinView(st, ctx, &st.fxPose, viewR);

    benchStep(st, mathx.minF(rl.getFrameTime(), 0.05));
    renderBench(target(&bigRT, BIG_W, BIG_H), env, scene, st);
    blit(bigRT.?, viewR);
    rl.drawRectangleLinesEx(viewR, 1, ui.alpha(ui.TRIM, 110));

    const sig = elemfx.sig(st.elem);
    const x = box.x + w - INFO_W - BIG_PAD;
    var y = box.y + 52;
    const line = lineH();
    var buf: [72]u8 = undefined;
    hud.mono("signature", x, y, hud.MONO, ui.alpha(ui.TRIM, 230));
    y += line + 4;
    inline for (.{
        .{ "grav", sig.grav },
        .{ "speed", sig.speedLo },
        .{ "..hi", sig.speedHi },
        .{ "life", sig.lifeLo },
        .{ "..hi", sig.lifeHi },
        .{ "r0", sig.r0 },
        .{ "r1", sig.r1 },
        .{ "drag", sig.drag },
        .{ "stretch", sig.stretch },
    }) |row| {
        const s = std.fmt.bufPrintZ(&buf, "{s: <7}{d: >7.3}", .{ row[0], row[1] }) catch "";
        hud.mono(s, x, y, hud.MONO, ui.VALUE);
        y += line;
    }
    y += 4;
    inline for (.{ .{ "core", sig.core }, .{ "edge", sig.edge } }) |row| {
        hud.mono(row[0], x, y, hud.MONO, ui.alpha(ui.LABEL, 210));
        rl.drawRectangleRec(ui.rect(x + 56, y + 2, 46, line - 6), row[1]);
        y += line;
    }
    if (sig.cool) |cool| {
        hud.mono("cool", x, y, hud.MONO, ui.alpha(ui.LABEL, 210));
        rl.drawRectangleRec(ui.rect(x + 56, y + 2, 46, line - 6), cool);
        y += line;
    }
    y += 4;
    const marks = std.fmt.bufPrintZ(&buf, "inward {s}  ash {s}", .{
        if (sig.inward) "yes" else "no",
        if (sig.ash != null) "yes" else "no",
    }) catch "";
    hud.mono(marks, x, y, hud.MONO, ui.VALUE);
    y += line + 6;
    hud.mono("drag spins", x, y, hud.MONO, ui.alpha(ui.LABEL, 170));
    y += line;
    hud.mono("wheel zooms", x, y, hud.MONO, ui.alpha(ui.LABEL, 170));

    const by = box.y + box.h - FOOT_DROP;
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD, by, 74, 24), "Play", hud.MONO, false, "Fire the effect again, with the numbers printed beside it")) {
        st.fxT = 0;
        benchFire(st);
    }
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD + 78, by, 74, 24), "Clear", hud.MONO, false, "Kill every live particle on the bench")) benchClear(st);
    var cb: [96]u8 = undefined;
    const count = std.fmt.bufPrintZ(&cb, "{s} {s}   {d} live", .{ combat.elemName(st.elem), Verb.label(st.verb), liveParts(st) }) catch "";
    hud.mono(count, box.x + BIG_PAD + 164, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + box.w - 96, by, 80, 24), "Close", hud.MONO, false, "Shut the viewer and go back to the editor (Esc)")) return false;
    return true;
}

fn liveParts(st: *const State) usize {
    var n: usize = 0;
    for (st.fx) |q| {
        if (q.life > 0) n += 1;
    }
    return n;
}

pub fn draw(st: *State, env: *envmod.Env, scene: *gfx.Scene, ctx: *ui.Ctx) bool {
    switch (st.mode) {
        .effects => return benchPanel(st, env, scene, ctx),
        .volumes => return volumePanel(st, env, scene, ctx),
        .objects => {
            if (st.open) |k| {
                if (big(st, env, scene, ctx, k)) return true;
                st.open = null;
                st.grabbed = null;
                return true;
            }
            return gallery(st, env, scene, ctx);
        },
        .icons => {
            if (st.openIcon) |i| {
                if (bigIcon(st, ctx, i)) return true;
                st.openIcon = null;
                return true;
            }
            return galleryIcons(st, ctx);
        },
        .chars => {
            if (st.openChar) |i| {
                if (bigChar(st, env, scene, ctx, i)) return true;
                st.openChar = null;
                st.grabbed = null;
                return true;
            }
            return galleryChars(st, env, scene, ctx);
        },
    }
}

pub fn back(st: *State) bool {
    if (st.openIcon != null) {
        st.openIcon = null;
        return true;
    }
    if (st.openChar != null) {
        st.openChar = null;
        st.grabbed = null;
        return true;
    }
    if (st.open == null) return false;
    st.open = null;
    st.grabbed = null;
    return true;
}

test "THE CHARACTER BENCH'S SLAB, MEASURED — one live group per creature, taken when the tab is opened" {
    const MB = 1024.0 * 1024.0;
    const bytes = @sizeOf(CharSet);
    std.debug.print("\n  objview CharSet: {d:.1} MB over {d} groups\n", .{ @as(f64, @floatFromInt(bytes)) / MB, CHAR_GROUPS });
    try std.testing.expect(bytes < 512 * 1024 * 1024);
    try std.testing.expectEqual(@typeInfo(CharSet).@"struct".fields.len, CHAR_GROUPS);
}
