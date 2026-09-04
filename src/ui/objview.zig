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
const heromod = @import("../play/hero.zig");
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
    if (heroRef) |h| std.heap.c_allocator.destroy(h);
    heroRef = null;
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

/// THE FX BENCH — `elemfx`'s twelve cells, PLAYING. Four elements against three verbs, side by side and on a loop.
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
/// …and the hitch ceiling on ONE frame of it — `elemfx.POUR_CAP`, the same number the fight runs at. As a bare `8` it was UNDER what a 60 fps frame owes at `POUR_RATE` (9.3), so it was in permanent hitch.
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
    /// Which creature the shared roster is currently STANDING as. The gallery stomps slot 0 a cell at a time, so a body only stays alive while one is open and nothing else has drawn over it.
    charLive: ?usize = null,
    charPlay: bool = true,
    charSpin: f32 = 0,
    charDist: f32 = 7.0,
    charT: f32 = 0,
    charRuler: bool = false,

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

// ONE GROUP OF EACH, exactly as the game holds them — the group is every creature's own draw contract (model, flash, scale). Members are respawned into slot 0 per render, and a spawn poses before it returns.
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
/// One group per creature, so it GROWS WITH THE ROSTER and is measured by the test at the foot of this file: as a figure it read 112.4 MB and was 150.6 by the time anyone looked.
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
        .fungal_swordsman => .{ .top = 3.0, .bound = 2.6 },
        .fungal_magus => .{ .top = 3.2, .bound = 1.6 },
    };
}

/// THE BENCH RUNS THE CREATURE'S OWN `update`, NOT A KEYED REPLAY. The quarry is a DECOY at a settable range on a slow orbit — every input a decision is allowed to read (position, bearing, distance and its own clocks) — and the body is put back on the origin after each step.
const Drive = enum { group, member, point, hit, yank };

pub const CHAR_DRIVE = [_]struct { field: []const u8, drive: Drive, kinds: []const wf.FoeKind }{
    .{ .field = "warren", .drive = .group, .kinds = &.{.toad} },
    .{ .field = "line", .drive = .member, .kinds = &.{.archer} },
    .{ .field = "grief", .drive = .group, .kinds = &.{.ogre} },
    .{ .field = "band", .drive = .point, .kinds = &.{ .berserker, .priest, .slinger } },
    // No `brood_sac`: `CHAR_KINDS` leaves it off the shelf, so it is a body the bench never stands.
    .{ .field = "brood", .drive = .point, .kinds = &.{ .brood_mother, .broodling } },
    .{ .field = "muster", .drive = .group, .kinds = &.{ .shieldman, .greatsword } },
    .{ .field = "haunt", .drive = .point, .kinds = &.{ .shade, .mourner } },
    .{ .field = "swarm", .drive = .hit, .kinds = &.{.leechfly} },
    .{ .field = "grove", .drive = .yank, .kinds = &.{.rooted} },
    .{ .field = "cluster", .drive = .group, .kinds = &.{.shroom} },
    .{ .field = "warrens", .drive = .group, .kinds = &.{.delver} },
    .{ .field = "rite", .drive = .group, .kinds = &.{.necromancer} },
    .{ .field = "vigil", .drive = .group, .kinds = &.{.bone_knight} },
    .{ .field = "herd", .drive = .group, .kinds = &.{.fungal_deer} },
    .{ .field = "ring", .drive = .group, .kinds = &.{.mushroom_mage} },
    .{ .field = "host", .drive = .group, .kinds = &.{.spore_golem} },
    .{ .field = "marsh", .drive = .group, .kinds = &.{.fen_lurker} },
    .{ .field = "clatter", .drive = .group, .kinds = &.{.bone_skitterer} },
    .{ .field = "crypt", .drive = .group, .kinds = &.{.ancient_priest} },
    .{ .field = "belfry", .drive = .group, .kinds = &.{.tolling_hollow} },
    .{ .field = "bed", .drive = .group, .kinds = &.{.slumber_bloom} },
    .{ .field = "scorch", .drive = .group, .kinds = &.{.cinder_wake} },
    .{ .field = "gorge", .drive = .group, .kinds = &.{.rotgorger} },
    .{ .field = "stand", .drive = .group, .kinds = &.{.birchwight} },
    .{ .field = "pan", .drive = .group, .kinds = &.{.salt_husk} },
    .{ .field = "shoal", .drive = .group, .kinds = &.{ .fish_spearman, .fish_netter, .fish_shaman } },
    .{ .field = "roost", .drive = .group, .kinds = &.{.blinkbat} },
    .{ .field = "perch", .drive = .group, .kinds = &.{.owlbear} },
    .{ .field = "vanguard", .drive = .group, .kinds = &.{.fungal_swordsman} },
    .{ .field = "conclave", .drive = .group, .kinds = &.{.fungal_magus} },
};

comptime {
    @setEvalBranchQuota(30000);
    if (CHAR_DRIVE.len != CHAR_GROUPS) @compileError("objview: CHAR_DRIVE and CharSet disagree on how many groups there are");
    for (CHAR_DRIVE) |row| {
        if (!@hasField(CharSet, row.field)) @compileError("objview: CHAR_DRIVE names `" ++ row.field ++ "`, which is not a CharSet field");
    }
    for (CHAR_KINDS) |k| {
        var found = false;
        for (CHAR_DRIVE) |row| {
            for (row.kinds) |kk| {
                if (kk == k) found = true;
            }
        }
        if (!found) @compileError("objview: " ++ @tagName(k) ++ " has no CHAR_DRIVE row, so the bench can draw it but never play it");
    }
    // The shape is the group's OWN `update`, read off it rather than remembered: a callback added to one is a compile error here instead of a bench that silently stopped playing that creature.
    for (CHAR_DRIVE) |row| {
        const G = @FieldType(CharSet, row.field);
        if (row.drive == .member) {
            if (@hasDecl(G, "update")) @compileError("objview: `" ++ row.field ++ "` has a group `update` now — take it off .member");
            continue;
        }
        const n = @typeInfo(@TypeOf(G.update)).@"fn".params.len;
        const want: usize = if (row.drive == .group) 5 else 7;
        if (n != want) @compileError(std.fmt.comptimePrint(
            "objview: `{s}`.update takes {d} params, and its CHAR_DRIVE row says {d}",
            .{ row.field, n, want },
        ));
    }
}

/// The bench's own world: wide enough that `stepXZ` never clamps inside one step of the treadmill.
const BENCH_BOUNDS: f32 = 400.0;
pub const BENCH_NEAR: f32 = 1.6;
pub const BENCH_FAR: f32 = 26.0;
const BENCH_ORBIT: f32 = 0.22; // radians a second the decoy walks round him

const Decoy = struct {};
fn decoyPoint(_: Decoy, _: rl.Vector3) void {}
fn decoyHit(_: Decoy, _: combat.Hit) void {}
fn decoyYank(_: Decoy, _: rl.Vector3, _: f32) void {}

pub fn quarryAt(dist: f32, spin: f32) rl.Vector3 {
    return v3(mathx.sinf(spin) * dist, 0, mathx.cosf(spin) * dist);
}

fn stepChar(cs: *CharSet, k: wf.FoeKind, dt: f32, quarry: rl.Vector3) void {
    inline for (CHAR_DRIVE) |row| {
        for (row.kinds) |kk| {
            if (kk != k) continue;
            const gr = &@field(cs, row.field);
            if (gr.n == 0) return;
            switch (row.drive) {
                .group => _ = gr.update(dt, quarry, BENCH_BOUNDS, .{}),
                .member => _ = gr.live()[0].update(dt, quarry, BENCH_BOUNDS, .{}),
                .point => _ = gr.update(dt, quarry, BENCH_BOUNDS, .{}, Decoy{}, decoyPoint),
                .hit => _ = gr.update(dt, quarry, BENCH_BOUNDS, .{}, Decoy{}, decoyHit),
                .yank => _ = gr.update(dt, quarry, BENCH_BOUNDS, .{}, Decoy{}, decoyYank),
            }
            // XZ only: `pos.y` is the GROUND under a body, and a flyer's whole height is measured off it.
            gr.live()[0].pos.x = 0;
            gr.live()[0].pos.z = 0;
            return;
        }
    }
}

fn drawGroup(cs: *CharSet, k: wf.FoeKind, scene: *gfx.Scene) void {
    inline for (CHAR_DRIVE) |row| {
        for (row.kinds) |kk| {
            if (kk == k) {
                @field(cs, row.field).draw(scene);
                return;
            }
        }
    }
}

fn drawChar(cs: *CharSet, k: wf.FoeKind, scene: *gfx.Scene) void {
    seedChar(cs, k);
    drawGroup(cs, k, scene);
}

fn seedChar(cs: *CharSet, k: wf.FoeKind) void {
    const seed = 0.35;
    switch (k) {
        .toad => {
            cs.warren.n = 1;
            cs.warren.live()[0] = frogmod.Frog.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .archer => {
            cs.line.n = 1;
            cs.line.live()[0] = archermod.Archer.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .ogre => {
            cs.grief.n = 1;
            cs.grief.live()[0] = ogremod.Ogre.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .berserker, .priest, .slinger => {
            const role: koboldmod.Role = switch (k) {
                .berserker => .berserker,
                .priest => .priest,
                else => .slinger,
            };
            cs.band.n = 1;
            cs.band.live()[0] = koboldmod.Kobold.spawnAs(role, mathx.zero3, 0, 1.0, seed);
        },
        .brood_mother, .broodling, .brood_sac => {
            const role: broodmod.Role = if (k == .broodling) .broodling else .mother;
            cs.brood.n = 1;
            cs.brood.live()[0] = broodmod.Spider.spawnAs(role, mathx.zero3, 0, 1.0, seed);
        },
        .shieldman, .greatsword => {
            cs.muster.n = 1;
            cs.muster.live()[0] = warriormod.Warrior.spawnAs(if (k == .shieldman) .shieldman else .greatsword, mathx.zero3, 0, 1.0, seed);
        },
        .fish_spearman, .fish_netter, .fish_shaman => {
            cs.shoal.n = 1;
            cs.shoal.live()[0] = fishmod.Fishman.spawnAs(fishmod.roleOf(k).?, mathx.zero3, 0, 1.0, seed);
        },
        .blinkbat => {
            cs.roost.n = 1;
            cs.roost.live()[0] = batmod.Bat.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .owlbear => {
            cs.perch.n = 1;
            cs.perch.live()[0] = owlbearmod.Owlbear.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .salt_husk => {
            cs.pan.n = 1;
            cs.pan.live()[0] = huskmod.Husk.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .birchwight => {
            cs.stand.n = 1;
            cs.stand.live()[0] = birchmod.Wight.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .rotgorger => {
            cs.gorge.n = 1;
            cs.gorge.live()[0] = gorgermod.Gorger.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .cinder_wake => {
            cs.scorch.n = 1;
            cs.scorch.live()[0] = cindermod.Cinder.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .slumber_bloom => {
            cs.bed.n = 1;
            cs.bed.live()[0] = bloommod.Bloom.spawn(mathx.zero3, 0, 1.0, seed);
            cs.bed.live()[0].debugWake();
            cs.bed.live()[0].open = 1;
            cs.bed.live()[0].pose();
        },
        .shade, .mourner => {
            cs.haunt.n = 1;
            cs.haunt.live()[0] = shademod.Shade.spawnAs(if (k == .mourner) .mourner else .shade, mathx.zero3, 0, 1.0, seed);
        },
        .leechfly => {
            cs.swarm.n = 1;
            cs.swarm.live()[0] = leechmod.Leechfly.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .rooted => {
            cs.grove.n = 1;
            var t = rootedmod.Rooted.spawn(mathx.zero3, 0, 1.0, seed);
            t.open = 1;
            t.eyes = 1;
            t.pose();
            cs.grove.live()[0] = t;
        },
        .shroom => {
            cs.cluster.n = 1;
            cs.cluster.live()[0] = shroommod.Shroom.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .bone_knight => {
            cs.vigil.n = 1;
            cs.vigil.live()[0] = knightmod.Knight.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .delver => {
            cs.warrens.n = 1;
            cs.warrens.live()[0] = delvermod.Delver.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .necromancer => {
            cs.rite.n = 1;
            cs.rite.live()[0] = necromod.Necro.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .fungal_deer => {
            cs.herd.n = 1;
            cs.herd.live()[0] = deermod.Deer.spawn(mathx.zero3, 0, 1.0, seed);
            cs.herd.live()[0].stageGather(1.0);
        },
        .spore_golem => {
            cs.host.n = 1;
            cs.host.live()[0] = golemmod.Golem.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .mushroom_mage => {
            cs.ring.n = 1;
            cs.ring.live()[0] = magemod.Mage.spawn(mathx.zero3, 0, 1.0, seed);
            cs.ring.live()[0].stageGather(1.0);
        },
        .fen_lurker => {
            cs.marsh.n = 1;
            cs.marsh.live()[0] = fenmod.Lurker.spawn(mathx.zero3, 0, 1.0, seed);
            cs.marsh.live()[0].stageGather(1.0);
        },
        .bone_skitterer => {
            cs.clatter.n = 1;
            cs.clatter.live()[0] = skittermod.Skitterer.spawn(mathx.zero3, 0, 1.0, seed);
            cs.clatter.live()[0].stageGather(0.85);
        },
        .ancient_priest => {
            cs.crypt.n = 1;
            cs.crypt.live()[0] = priestmod.Ancient.spawn(mathx.zero3, 0, 1.0, seed);
            cs.crypt.live()[0].stageGather(1.0);
        },
        .tolling_hollow => {
            cs.belfry.n = 1;
            cs.belfry.live()[0] = hollowmod.Hollow.spawn(mathx.zero3, 0, 1.0, seed);
            cs.belfry.live()[0].stageGather(0.9);
        },
        .fungal_swordsman => {
            cs.vanguard.n = 1;
            cs.vanguard.live()[0] = duomod.Swordsman.spawn(mathx.zero3, 0, 1.0, seed);
        },
        .fungal_magus => {
            cs.conclave.n = 1;
            cs.conclave.live()[0] = duomod.Magus.spawn(mathx.zero3, 0, 1.0, seed);
        },
    }
}

/// A LONE BODY IN A FITTED FRAME HAS NO SCALE — every creature is drawn to fill the same box, so a salt husk and an ogre read the same size. The hero is the ruler: his 1.8 m is the one height the eye already knows.
const RULER_GAP: f32 = 0.6;

var heroRef: ?*heromod.Hero = null;

fn ensureHero(scene: *gfx.Scene) *heromod.Hero {
    if (heroRef) |h| return h;
    const h = std.heap.c_allocator.create(heromod.Hero) catch @panic("objview: the ruler");
    heroRef = h;
    h.* = heromod.Hero.init(scene.shader);
    return h;
}

fn rulerStandX(bound: f32) f32 {
    return bound * 0.5 + RULER_GAP + foemod.HERO_R;
}

fn renderChar(rt: rl.RenderTexture2D, env: *envmod.Env, scene: *gfx.Scene, k: wf.FoeKind, pose: Pose, live: bool, ruler: bool) void {
    const cs = ensureChars(scene);
    const dims = charDims(k);
    const aspect = rtAspect(rt);
    const standX = rulerStandX(dims.bound);
    const top = if (ruler) mathx.maxF(dims.top, heromod.H) else dims.top;
    const bound = if (ruler) mathx.maxF(dims.bound, (standX + foemod.HERO_R) * 2.0) else dims.bound;
    openStage(rt, env, scene, fitCam(top, bound, pose, aspect), aspect);
    if (live) drawGroup(cs, k, scene) else drawChar(cs, k, scene);
    if (ruler) {
        const h = ensureHero(scene);
        h.pos = v3(standX, 0, 0);
        h.facing = 0;
        h.pose();
        h.draw(false);
    }
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

    st.charLive = null;
    i = start;
    while (i < end) : (i += 1) {
        const k = CHAR_KINDS[i];
        const r = gridCell(box, @intCast(i - start));
        renderChar(target(&thumbRT, THUMB_W, THUMB_H), env, scene, k, st.charPose[i], false, false);
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

    const cs = ensureChars(scene);
    if (st.charLive == null or st.charLive.? != at) {
        seedChar(cs, k);
        st.charLive = at;
        st.charSpin = 0;
        st.charT = 0;
    }
    if (st.charPlay) {
        const dt = mathx.minF(rl.getFrameTime(), 0.05);
        st.charT += dt;
        st.charSpin += BENCH_ORBIT * dt;
        stepChar(cs, k, dt, quarryAt(st.charDist, st.charSpin));
    }
    renderChar(target(&bigRT, BIG_W, BIG_H), env, scene, k, p.*, true, st.charRuler);
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
    y += 6;
    if (ui.button(ctx, ui.rect(x, y, 78, 24), if (st.charPlay) "Pause" else "Play", hud.MONO, st.charPlay, "Run the creature's own update against a decoy. It walks, turns, closes and strikes on its own")) {
        st.charPlay = !st.charPlay;
    }
    if (ui.button(ctx, ui.rect(x + 82, y, 78, 24), "Restart", hud.MONO, false, "Put it back on its own first frame")) {
        seedChar(cs, k);
        st.charSpin = 0;
        st.charT = 0;
    }
    y += 30;
    _ = ui.checkbox(ctx, x, y, "hero beside it", &st.charRuler, "Stand the hero next to it at his own 1.8 m. Every creature is fitted to the same frame, so this is the only thing that says how big one is");
    y += 24;
    _ = ui.slider(ctx, x, y, INFO_W - 12, "decoy range (m)", &st.charDist, BENCH_NEAR, BENCH_FAR, "Where the decoy stands. Inside its reach it strikes, outside it closes, past its own aggro it walks its post");
    y += ui.ROW_H + 14;
    const clock = std.fmt.bufPrintZ(&buf, "{s: <7}{d: >7.1}", .{ "played", st.charT }) catch "";
    hud.mono(clock, x, y, hud.MONO, ui.alpha(ui.VALUE, if (st.charPlay) 255 else 140));
    y += line + 8;
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
    // Framed on the volume's OWN reach, not on a fixed box: a 1.55 m pool and a 1.9 m cloud want different cameras.
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

test "THE RULER STANDS IN FRAME BESIDE EVERY CREATURE — every body is fitted to the same box, which is exactly what hides its size" {
    const aspect = @as(f32, @floatFromInt(BIG_W)) / @as(f32, @floatFromInt(BIG_H));
    var tallest: f32 = 0;
    var tallName: [:0]const u8 = "";
    var shortest: f32 = 1e9;
    var shortName: [:0]const u8 = "";
    for (CHAR_KINDS) |k| {
        const dims = charDims(k);
        const standX = rulerStandX(dims.bound);
        const top = mathx.maxF(dims.top, heromod.H);
        const bound = mathx.maxF(dims.bound, (standX + foemod.HERO_R) * 2.0);
        const view = envmod.View.fromCamera(fitCam(top, bound, .{}, aspect), aspect);
        const pts = [_]rl.Vector3{
            v3(0, dims.top, 0),          v3(0, 0, 0),
            v3(standX, heromod.H, 0),    v3(standX, 0, 0),
        };
        for (pts) |q| try std.testing.expect(view.visible(q, 0, 1e6));
        if (dims.top > tallest) {
            tallest = dims.top;
            tallName = wf.foeName(k);
        }
        if (dims.top < shortest) {
            shortest = dims.top;
            shortName = wf.foeName(k);
        }
    }
    std.debug.print("\n  ruler: hero {d:.2} m against {s} at {d:.2} ({d:.2}x) and {s} at {d:.2} ({d:.2}x) — both in frame for all {d}\n", .{
        heromod.H,  tallName,  tallest,  tallest / heromod.H,
        shortName,  shortest,  shortest / heromod.H,  CHAR_KINDS.len,
    });
}

test "EVERY CREATURE ON THE BENCH CAN BE PLAYED, and the decoy is the only thing it is told" {
    var kinds: usize = 0;
    var member: usize = 0;
    var withSpawn: usize = 0;
    inline for (CHAR_DRIVE) |row| {
        kinds += row.kinds.len;
        if (row.drive == .member) member += 1;
        if (row.drive == .point or row.drive == .hit or row.drive == .yank) withSpawn += 1;
    }
    try std.testing.expectEqual(CHAR_KINDS.len, kinds);

    // The decoy is a POSITION at a range and nothing else — it carries no state a decision could read.
    try std.testing.expect(BENCH_NEAR > 0 and BENCH_FAR > BENCH_NEAR);
    var far: f32 = 0;
    var spin: f32 = 0;
    while (spin < std.math.tau) : (spin += 0.1) {
        const q = quarryAt(BENCH_FAR, spin);
        try std.testing.expectApproxEqAbs(@as(f32, 0), q.y, 1e-6);
        far = @max(far, mathx.lenXZ(q));
        try std.testing.expectApproxEqAbs(BENCH_FAR, mathx.lenXZ(q), 1e-3);
    }
    std.debug.print(
        "\n  bench roster: {d} creatures over {d} groups — {d} driven per body, {d} through a spawn callback\n" ++
            "  decoy walks a {d:.0} m ring at {d:.2} rad/s, {d:.1}..{d:.1} m of range\n",
        .{ kinds, CHAR_DRIVE.len, member, withSpawn, far, BENCH_ORBIT, BENCH_NEAR, BENCH_FAR },
    );
}
