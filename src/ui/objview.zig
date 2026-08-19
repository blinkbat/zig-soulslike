const std = @import("std");
const rl = @import("raylib");

const envmod = @import("../world/env.zig");
const gfx = @import("../gfx/gfx.zig");
const hud = @import("hud.zig");
const mathx = @import("../core/mathx.zig");
const props = @import("../props/props.zig");
const ui = @import("ui.zig");
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
const ravagermod = @import("../foes/ravager.zig");
const magemod = @import("../foes/shroommage.zig");
const fenmod = @import("../foes/fenlurker.zig");
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
}

pub const Mode = enum {
    objects,
    icons,
    chars,
    effects,

    fn label(m: Mode) [:0]const u8 {
        return switch (m) {
            .objects => "Objects",
            .icons => "Icons",
            .chars => "Characters",
            .effects => "Effects",
        };
    }
};

/// **THE FX BENCH — `elemfx`'s twelve cells, PLAYING.** The jukebox's arrangement one gallery along: the
/// sounds are auditioned there because a waveform on a page tells you nothing, and a particle signature is
/// the same problem — `lifeHi 1.15` is not a thing anybody can picture. Four elements against three verbs,
/// side by side and on a loop, with the numbers being tuned printed beside them.
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
/// …and the hitch ceiling on ONE frame of it — `elemfx.POUR_CAP`, the same number the fight runs at, because
/// a bench throttled differently from the thing it is tuning is a bench that lies. As a bare `8` it was UNDER
/// what a 60 fps frame owes at `POUR_RATE` (9.3), so it was in permanent hitch: dropping arrears every frame
/// and drawing a stream at 480 motes a second against the fight's 560.
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

fn render(rt: rl.RenderTexture2D, env: *envmod.Env, scene: *gfx.Scene, kind: Kind, pose: Pose) void {
    const nfo = props.info(kind);
    const aspect = @as(f32, @floatFromInt(rt.texture.width)) / @as(f32, @floatFromInt(rt.texture.height));
    const cam = camFor(nfo, pose, aspect);
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
    scene.setWind(nfo.flora);
    rl.drawModel(env.model(kind), mathx.zero3, 1.0, rl.Color.white);
    if (env.veil(kind)) |v| rl.drawModel(v, mathx.zero3, 1.0, rl.Color.white);
    scene.setWind(false);
    rl.endMode3D();
    rl.endTextureMode();
}

// ONE GROUP OF EACH, exactly as the game holds them — the group is every creature's own draw contract
// (model, flash, scale), so the viewer cannot drift from what the field shows. Members are respawned into
// slot 0 per render; a spawn poses before it returns, so the cell is the creature's own first frame.
const CharSet = struct {
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
    thicket: ravagermod.Thicket,
    ring: magemod.Ring,
    marsh: fenmod.Marsh,
};
var charSet: ?CharSet = null;

fn ensureChars(scene: *gfx.Scene) *CharSet {
    if (charSet == null) {
        charSet = .{
            .warren = frogmod.Knot.init(scene.shader),
            .line = archermod.Line.init(scene.shader),
            .grief = ogremod.Grief.init(scene.shader),
            .band = koboldmod.Warband.init(scene.shader),
            .brood = broodmod.Brood.init(scene.shader),
            .muster = warriormod.Muster.init(scene.shader),
            .haunt = shademod.Haunt.init(scene.shader),
            .swarm = leechmod.Swarm.init(scene.shader),
            .grove = rootedmod.Grove.init(scene.shader),
            .cluster = shroommod.Cluster.init(scene.shader),
            .warrens = delvermod.Warrens.init(scene.shader),
            .rite = necromod.Rite.init(scene.shader),
            .vigil = knightmod.Vigil.init(scene.shader),
            .thicket = ravagermod.Thicket.init(scene.shader),
            .ring = magemod.Ring.init(scene.shader),
            .marsh = fenmod.Marsh.init(scene.shader),
        };
        var cs = &charSet.?;
        cs.warren.n = 0;
        cs.line.n = 0;
        cs.grief.n = 0;
        cs.band.n = 0;
        cs.brood.n = 0;
        cs.muster.n = 0;
        cs.haunt.n = 0;
        cs.swarm.n = 0;
        cs.grove.n = 0;
        cs.cluster.n = 0;
        cs.warrens.n = 0;
        cs.vigil.n = 0;
        cs.thicket.n = 0;
        cs.ring.n = 0;
    }
    return &charSet.?;
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
        .leechfly => .{ .top = 2.9, .bound = 1.8 },
        .rooted => .{ .top = 7.2, .bound = 3.6 },
        .shroom => .{ .top = 1.2, .bound = 1.0 },
        .bone_knight => .{ .top = 5.4, .bound = 3.2 },
        .delver => .{ .top = 1.9, .bound = 2.0 },
        .necromancer => .{ .top = 2.8, .bound = 1.3 },
        .florid_ravager => .{ .top = 1.9, .bound = 2.2 },
        .mushroom_mage => .{ .top = 1.6, .bound = 1.4 },
        .fen_lurker => .{ .top = 2.9, .bound = 1.1 },
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
        .shade => {
            cs.haunt.n = 1;
            cs.haunt.live()[0] = shademod.Shade.spawn(mathx.zero3, 0, 1.0, seed);
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
        .florid_ravager => {
            cs.thicket.n = 1;
            cs.thicket.live()[0] = ravagermod.Ravager.spawn(mathx.zero3, 0, 1.0, seed);
            cs.thicket.live()[0].stageGather(1.0);
            cs.thicket.draw(scene);
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
    }
}

fn renderChar(rt: rl.RenderTexture2D, env: *envmod.Env, scene: *gfx.Scene, k: wf.FoeKind, pose: Pose) void {
    const cs = ensureChars(scene);
    const dims = charDims(k);
    const aspect = @as(f32, @floatFromInt(rt.texture.width)) / @as(f32, @floatFromInt(rt.texture.height));
    const cam = fitCam(dims.top, dims.bound, pose, aspect);
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
    drawChar(cs, k, scene);
    rl.endMode3D();
    rl.endTextureMode();
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
        if (ui.chip(ctx, tx, y, m.label(), st.mode == m, &usedW) and st.mode != m) {
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
        if (ui.chip(ctx, tx, ty, s.label(), st.shelf == s, &usedW) and st.shelf != s) {
            st.shelf = s;
            st.page = 0;
            st.grabbed = null;
        }
        tx += usedW;
    }

    const start: usize = @intCast(st.page * perPage());
    const end = @min(start + @as(usize, @intCast(perPage())), list.len);
    const gridX = box.x + 16;
    const gridY = box.y + HEADER;

    var hover: ?usize = null;
    var hoverRect: rl.Rectangle = undefined;
    var i = start;
    while (i < end) : (i += 1) {
        const slot: i32 = @intCast(i - start);
        const r = ui.rect(
            gridX + @mod(slot, COLS) * cellW(),
            gridY + @divTrunc(slot, COLS) * cellH(),
            THUMB_W,
            THUMB_H,
        );
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
        const slot: i32 = @intCast(i - start);
        const r = ui.rect(
            gridX + @mod(slot, COLS) * cellW(),
            gridY + @divTrunc(slot, COLS) * cellH(),
            THUMB_W,
            THUMB_H,
        );
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
    if (ui.button(ctx, ui.rect(box.x + 16, by, 44, 24), "<", hud.MONO, false)) st.page = @max(0, st.page - 1);
    if (ui.button(ctx, ui.rect(box.x + 64, by, 44, 24), ">", hud.MONO, false)) st.page = @min(pages - 1, st.page + 1);
    var buf: [96]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "page {d}/{d}   {d} objects   drag spins, wheel zooms, click opens", .{ st.page + 1, pages, list.len }) catch "";
    hud.mono(s, box.x + 120, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + box.w - 96, by, 80, 24), "Close", hud.MONO, false)) return false;
    return true;
}


const BIG_PAD: i32 = 16;
const INFO_W: i32 = 250;

/// **DRAG SPINS, WHEEL ZOOMS — ONE COPY.** The three modals (a prop, a creature, the FX bench) each had this
/// nine-line block written out, so a rate or a clamp retuned in one of them left the other two turning
/// differently.
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
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD, by, 44, 24), "<", hud.MONO, false)) {
        st.open = list[if (at == 0) list.len - 1 else at - 1];
    }
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD + 48, by, 44, 24), ">", hud.MONO, false)) {
        st.open = list[if (at + 1 >= list.len) 0 else at + 1];
    }
    var cb: [64]u8 = undefined;
    const count = std.fmt.bufPrintZ(&cb, "{d}/{d} in {s}", .{ at + 1, list.len, st.shelf.label() }) catch "";
    hud.mono(count, box.x + BIG_PAD + 104, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + box.w - 176, by, 74, 24), "Reset", hud.MONO, false)) p.* = .{};
    if (ui.button(ctx, ui.rect(box.x + box.w - 96, by, 80, 24), "Back", hud.MONO, false)) return false;
    return true;
}


fn galleryChars(st: *State, env: *envmod.Env, scene: *gfx.Scene, ctx: *ui.Ctx) bool {
    const pages = pageCount(CHAR_N);
    st.page = clampI(st.page, 0, pages - 1);
    const box = ui.beginModal(ctx, modalW(), modalH(), "Object viewer");
    if (modeTabs(st, ctx, box.x + 16, box.y + 44).changed) return true;

    const start: usize = @intCast(st.page * perPage());
    const end = @min(start + @as(usize, @intCast(perPage())), CHAR_N);
    const gridX = box.x + 16;
    const gridY = box.y + HEADER;

    var hover: ?usize = null;
    var i = start;
    while (i < end) : (i += 1) {
        const slot: i32 = @intCast(i - start);
        const r = ui.rect(gridX + @mod(slot, COLS) * cellW(), gridY + @divTrunc(slot, COLS) * cellH(), THUMB_W, THUMB_H);
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
        const slot: i32 = @intCast(i - start);
        const r = ui.rect(gridX + @mod(slot, COLS) * cellW(), gridY + @divTrunc(slot, COLS) * cellH(), THUMB_W, THUMB_H);
        renderChar(target(&thumbRT, THUMB_W, THUMB_H), env, scene, k, st.charPose[i]);
        blit(thumbRT.?, r);
        const on = (hover != null and hover.? == i) or (st.grabbed != null and st.grabbed.? == i);
        rl.drawRectangleLinesEx(r, 1, ui.alpha(if (on) ui.HOT else ui.TRIM, if (on) 220 else 70));
        const name = wf.foeName(k);
        const nw = hud.monoW(name, hud.MONO);
        hud.mono(name, @as(i32, @intFromFloat(r.x)) + @divTrunc(THUMB_W - nw, 2), @as(i32, @intFromFloat(r.y + r.height)) + 3, hud.MONO, if (on) ui.HOT else ui.LABEL);
    }

    const by = box.y + box.h - FOOT_DROP;
    if (ui.button(ctx, ui.rect(box.x + 16, by, 44, 24), "<", hud.MONO, false)) st.page = @max(0, st.page - 1);
    if (ui.button(ctx, ui.rect(box.x + 64, by, 44, 24), ">", hud.MONO, false)) st.page = @min(pages - 1, st.page + 1);
    var buf: [96]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "page {d}/{d}   {d} characters   drag spins, wheel zooms, click opens", .{ st.page + 1, pages, CHAR_N }) catch "";
    hud.mono(s, box.x + 120, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + box.w - 96, by, 80, 24), "Close", hud.MONO, false)) return false;
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
    y += 6;
    hud.mono("drag spins", x, y, hud.MONO, ui.alpha(ui.LABEL, 170));
    y += line;
    hud.mono("wheel zooms", x, y, hud.MONO, ui.alpha(ui.LABEL, 170));

    const by = box.y + box.h - FOOT_DROP;
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD, by, 44, 24), "<", hud.MONO, false)) st.openChar = if (at == 0) CHAR_N - 1 else at - 1;
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD + 48, by, 44, 24), ">", hud.MONO, false)) st.openChar = if (at + 1 >= CHAR_N) 0 else at + 1;
    var cb: [64]u8 = undefined;
    const count = std.fmt.bufPrintZ(&cb, "{d}/{d} characters", .{ at + 1, CHAR_N }) catch "";
    hud.mono(count, box.x + BIG_PAD + 104, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + box.w - 176, by, 74, 24), "Reset", hud.MONO, false)) p.* = .{};
    if (ui.button(ctx, ui.rect(box.x + box.w - 96, by, 80, 24), "Back", hud.MONO, false)) return false;
    return true;
}

fn galleryIcons(st: *State, ctx: *ui.Ctx) bool {
    const pages = pageCount(ICONS_TOTAL);
    st.page = clampI(st.page, 0, pages - 1);
    const box = ui.beginModal(ctx, modalW(), modalH(), "Object viewer");
    if (modeTabs(st, ctx, box.x + 16, box.y + 44).changed) return true;

    const start: usize = @intCast(st.page * perPage());
    const end = @min(start + @as(usize, @intCast(perPage())), ICONS_TOTAL);
    const gridX = box.x + 16;
    const gridY = box.y + HEADER;
    var hover: ?usize = null;
    var i = start;
    while (i < end) : (i += 1) {
        const slot: i32 = @intCast(i - start);
        const r = ui.rect(gridX + @mod(slot, COLS) * cellW(), gridY + @divTrunc(slot, COLS) * cellH(), THUMB_W, THUMB_H);
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
    if (ui.button(ctx, ui.rect(box.x + 16, by, 44, 24), "<", hud.MONO, false)) st.page = @max(0, st.page - 1);
    if (ui.button(ctx, ui.rect(box.x + 64, by, 44, 24), ">", hud.MONO, false)) st.page = @min(pages - 1, st.page + 1);
    var buf: [96]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "page {d}/{d}   {d} glyphs + {d} pictures   click enlarges", .{ st.page + 1, pages, GLYPH_N, PICT_N }) catch "";
    hud.mono(s, box.x + 120, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + box.w - 96, by, 80, 24), "Close", hud.MONO, false)) return false;
    return true;
}

fn bigIcon(st: *State, ctx: *ui.Ctx, at: usize) bool {
    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    const w = @min(sw - 60, 720);
    const h = @min(sh - 60, 640);
    const box = ui.beginModal(ctx, w, h, iconLabel(at));
    const cx = @as(f32, @floatFromInt(box.x)) + @as(f32, @floatFromInt(w)) * 0.5;
    const cy = @as(f32, @floatFromInt(box.y)) + @as(f32, @floatFromInt(h)) * 0.5;
    drawIconAt(at, cx, cy, @as(f32, @floatFromInt(@min(w, h))) * 0.62);

    const by = box.y + box.h - FOOT_DROP;
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD, by, 44, 24), "<", hud.MONO, false)) st.openIcon = if (at == 0) ICONS_TOTAL - 1 else at - 1;
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD + 48, by, 44, 24), ">", hud.MONO, false)) st.openIcon = if (at + 1 >= ICONS_TOTAL) 0 else at + 1;
    if (ui.button(ctx, ui.rect(box.x + box.w - 96, by, 80, 24), "Back", hud.MONO, false)) return false;
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
    const aspect = @as(f32, @floatFromInt(rt.texture.width)) / @as(f32, @floatFromInt(rt.texture.height));
    const wide = st.verb == .pour;
    const cam = fitCam(if (wide) 2.4 else 1.7, if (wide) combat.RIME_REACH * 0.62 else 1.1, st.fxPose, aspect);
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
    foemod.drawParticles(&st.fx);
    rl.endMode3D();
    rl.endTextureMode();
}

fn benchPanel(st: *State, env: *envmod.Env, scene: *gfx.Scene, ctx: *ui.Ctx) bool {
    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    const w = @min(sw - 60, BIG_W + INFO_W + 3 * BIG_PAD);
    const h = @min(sh - 60, BIG_H + 130);
    const box = ui.beginModal(ctx, w, h, "Effects bench");
    if (modeTabs(st, ctx, box.x + 16, box.y + 44).changed) return true;

    // THE GRID ITSELF, as two rows of chips: the element down one and the verb down the other, which is
    // twelve cells reachable in two clicks rather than a page of thumbnails that cannot move.
    var tx = box.x + 16;
    const ey = box.y + 78;
    inline for (@typeInfo(combat.Elem).@"enum".fields) |f| {
        const e: combat.Elem = @enumFromInt(f.value);
        var usedW: i32 = 0;
        if (ui.chip(ctx, tx, ey, combat.elemName(e), st.elem == e, &usedW) and st.elem != e) {
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
        if (ui.chip(ctx, tx, vy, v.label(), st.verb == v, &usedW) and st.verb != v) {
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
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD, by, 74, 24), "Play", hud.MONO, false)) {
        st.fxT = 0;
        benchFire(st);
    }
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD + 78, by, 74, 24), "Clear", hud.MONO, false)) benchClear(st);
    var cb: [96]u8 = undefined;
    const count = std.fmt.bufPrintZ(&cb, "{s} {s}   {d} live", .{ combat.elemName(st.elem), Verb.label(st.verb), liveParts(st) }) catch "";
    hud.mono(count, box.x + BIG_PAD + 164, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + box.w - 96, by, 80, 24), "Close", hud.MONO, false)) return false;
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
