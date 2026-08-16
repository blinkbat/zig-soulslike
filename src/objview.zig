const std = @import("std");
const rl = @import("raylib");

const envmod = @import("env.zig");
const gfx = @import("gfx.zig");
const hud = @import("hud.zig");
const mathx = @import("mathx.zig");
const props = @import("props.zig");
const ui = @import("ui.zig");
const icons = @import("icons.zig");
const item = @import("item.zig");
const itemart = @import("itemart.zig");
const wf = @import("worldfmt.zig");
const frogmod = @import("frog.zig");
const archermod = @import("archer.zig");
const ogremod = @import("ogre.zig");
const koboldmod = @import("kobold.zig");
const broodmod = @import("brood.zig");
const warriormod = @import("warrior.zig");
const shademod = @import("shade.zig");
const leechmod = @import("leechfly.zig");
const rootedmod = @import("rooted.zig");
const shroommod = @import("shroom.zig");
const knightmod = @import("knight.zig");
const delvermod = @import("delver.zig");
const necromod = @import("necro.zig");
const combat = @import("combat.zig");
const foemod = @import("foe.zig");
const elemfx = @import("elemfx.zig"); // the elements' particle LANGUAGE — the bench is where it is TUNED

const v3 = mathx.v3;
const Kind = props.Kind;


/// The layer shelves the gallery offers — one per layer that places props, off `props.Stock`.
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

// The default three-quarter view, and the pitch rails.
const BASE_YAW: f32 = 0.62;
const BASE_PITCH: f32 = 0.34;
const MIN_PITCH: f32 = -0.12; // a hair below level — enough to check that a base is planted
const MAX_PITCH: f32 = 1.35;
const MIN_ZOOM: f32 = 0.45;
const MAX_ZOOM: f32 = 4.0;
const ROT_RATE: f32 = 0.008; // radians per pixel of drag
const CLICK_SLOP = ui.DRAG_PX;
const ZOOM_RATE: f32 = 0.12; // per wheel notch

/// How far back "fit" is, as a multiple of the kind's own bounding radius.
const FIT: f32 = 2.05;

const BACKDROP = mathx.rgba(52, 48, 40, 255);

// The off-screen targets, at FIXED sizes and shared by every cell: a fixed size keeps a window resize from
// unloading and reloading a render texture mid-frame, which is a crash and not a hiccup.
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

/// WHICH GALLERY IS UP: the props it always showed, the editor's whole 2D glyph set (unit icons and the
/// bag's item pictures), or the CHARACTERS — every creature the map can post, posed at the origin.
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
///
/// It draws through the SAME `elemfx` calls the game does. A bench with its own emitter is a bench that
/// agrees with nothing.
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
    /// Seconds between re-fires. The POUR does not loop — it is a stream, so it runs for as long as you are
    /// looking at it, which is also the only way to judge whether it holds together.
    fn loop(v: Verb) f32 {
        return switch (v) {
            .gather => 0.9,
            .burst => 1.1,
            .pour => 0,
        };
    }
};

/// Enough for the worst cell — the POUR, which is resident for its whole span where the other two are
/// bursts already dying. `elemfx`'s longest life against its own rate, and then some headroom, because a
/// bench that silently drops motes is a bench that lies about the thing being tuned.
const BENCH_FX_N = 256;
/// Where it fires from and which way it goes: chest height on the world's own forward, so the pour lies
/// along the same axis the hero breathes down.
const BENCH_AT = v3(0, 1.05, 0);
const BENCH_DIR = v3(0, 0, -1);

/// Every character, minus the egg sac — one membrane on the ground is not a character (the mark test's
/// own exemption, for the mark test's own reason).
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
    /// The object the big viewer is showing; `null` = the gallery is up.
    open: ?Kind = null,
    /// …and its counterparts on the other two galleries.
    openIcon: ?usize = null,
    openChar: ?usize = null,
    /// Per-kind pose, so turning something over and coming back to it later finds it as you left it.
    pose: [props.NK]Pose = [_]Pose{.{}} ** props.NK,
    charPose: [CHAR_N]Pose = [_]Pose{.{}} ** CHAR_N,
    grabbed: ?usize = null,
    travel: f32 = 0,
    /// THE FX BENCH's own state — which cell of `elemfx`'s grid is playing, and the pool it plays into.
    elem: combat.Elem = .cold,
    verb: Verb = .pour,
    fxPose: Pose = .{},
    fx: [BENCH_FX_N]foemod.Particle = [_]foemod.Particle{.{}} ** BENCH_FX_N,
    fxHead: usize = 0,
    /// Seconds since this cell last fired — the loop's clock, and the emitter's seed.
    fxT: f32 = 0,
    /// …and the pour's emission arrears, `hero.breathAcc`'s twin: the rate has to be independent of the
    /// frame rate here too, or the bench shows a different stream than the game does.
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
    // Framed off the kind's HEIGHT as well as its bound.
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
    // CULLED AGAINST THIS PREVIEW'S OWN FRUSTUM.
    const view = envmod.View.fromCamera(cam, aspect);
    env.drawGround(&view);
    scene.setGround(false);
    // FLORA SWAYS in the world, so it sways here — a fern judged rigid is a fern judged wrong.
    scene.setWind(nfo.flora);
    rl.drawModel(env.model(kind), mathx.zero3, 1.0, rl.Color.white);
    if (env.veil(kind)) |v| rl.drawModel(v, mathx.zero3, 1.0, rl.Color.white);
    scene.setWind(false);
    rl.endMode3D();
    rl.endTextureMode();
}

//
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
    }
    return &charSet.?;
}

/// The framing box a creature stands in — its crown and its spread, the two numbers `fitCam` frames off.
fn charDims(k: wf.FoeKind) struct { top: f32, bound: f32 } {
    return switch (k) {
        .toad => .{ .top = 1.7, .bound = 1.6 },
        .archer => .{ .top = 2.0, .bound = 1.0 },
        .ogre => .{ .top = 4.5, .bound = 2.4 },
        .berserker, .priest, .slinger => .{ .top = 1.7, .bound = 1.0 },
        .brood_mother => .{ .top = 2.8, .bound = 2.9 },
        .broodling => .{ .top = 1.2, .bound = 1.1 },
        .brood_sac => .{ .top = 1.2, .bound = 1.0 }, // never listed; a sane box if it ever is
        .shieldman, .greatsword => .{ .top = 2.1, .bound = 1.2 },
        .shade => .{ .top = 2.4, .bound = 1.2 },
        .leechfly => .{ .top = 2.9, .bound = 1.8 },
        .rooted => .{ .top = 7.2, .bound = 3.6 },
        .shroom => .{ .top = 1.2, .bound = 1.0 },
        .bone_knight => .{ .top = 5.4, .bound = 3.2 },
        .delver => .{ .top = 1.9, .bound = 2.0 },
        // TALL AND NARROW, and the box says so: nothing else on this list is more than twice as high as it
        // is wide. The bound has to hold the dragging hem, which is wider than the body above it.
        .necromancer => .{ .top = 2.8, .bound = 1.3 },
    };
}

/// Put ONE of `k` at the origin of its own group and draw that group. The rooted is woken by hand — the
/// whole point of its dormant pose is to be indistinguishable from a snag, which is a useless portrait.
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

/// One cell of the 2D set: the editor glyph in the set's own line colour, or the bag picture.
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
const HEADER: i32 = 78; // title band + the shelf tabs under it
const FOOTER: i32 = 44;
/// Drop from a panel's BOTTOM edge to its footer row — the gallery and the big viewer share it.
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

/// One row pitch for the readout column
fn lineH() i32 {
    return ui.ROW_H;
}

const clampI = mathx.clampI;

/// The SET pickers, one row on every gallery: which of the three collections is up. Returns where the
/// row got to, so the objects gallery can hang its shelf chips off the end of it.
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

    // GRAB → DRAG SPINS, RELEASE WITHOUT TRAVEL OPENS.
    if (ctx.pressed) {
        st.grabbed = hover;
        st.travel = 0;
    }
    // BOUNDS-CHECKED ON BOTH ARMS.
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
            if (st.travel <= CLICK_SLOP) st.open = list[g]; // in range: the arm above just checked it
            st.grabbed = null;
        }
    }

    // A render/blit pair per cell — twelve off-screen passes a frame, one model over a ground quad at 236x198.
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

    // Off the box's OWN extent, not a second call to the size functions it was built from.
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
const INFO_W: i32 = 250; // the readout column beside the object

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

    const overView = rl.checkCollisionPointRec(ctx.mouse, viewR);
    if (overView and ctx.wheel != 0) p.zoom = mathx.clampF(p.zoom * (1.0 + ZOOM_RATE * ctx.wheel), MIN_ZOOM, MAX_ZOOM);
    if (ctx.pressed and overView) st.grabbed = 0; // any non-null: this panel has one object
    if (st.grabbed != null) {
        if (rl.isMouseButtonDown(.left)) {
            const d = rl.getMouseDelta();
            p.yaw += d.x * ROT_RATE;
            p.pitch = mathx.clampF(p.pitch - d.y * ROT_RATE, MIN_PITCH, MAX_PITCH);
        } else st.grabbed = null;
    }

    render(target(&bigRT, BIG_W, BIG_H), env, scene, kind, p.*);
    blit(bigRT.?, viewR);
    rl.drawRectangleLinesEx(viewR, 1, ui.alpha(ui.TRIM, 110));

    // THE INFO COLUMN — every number the engine actually reads off this kind.
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

    const overView = rl.checkCollisionPointRec(ctx.mouse, viewR);
    if (overView and ctx.wheel != 0) p.zoom = mathx.clampF(p.zoom * (1.0 + ZOOM_RATE * ctx.wheel), MIN_ZOOM, MAX_ZOOM);
    if (ctx.pressed and overView) st.grabbed = 0;
    if (st.grabbed != null) {
        if (rl.isMouseButtonDown(.left)) {
            const d = rl.getMouseDelta();
            p.yaw += d.x * ROT_RATE;
            p.pitch = mathx.clampF(p.pitch - d.y * ROT_RATE, MIN_PITCH, MAX_PITCH);
        } else st.grabbed = null;
    }

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
        // The glyphs draw in the set's own line colour at gallery size; the pictures at their own scale.
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

/// Where the cell fires from. The POUR is started half its own reach UPWIND so the whole stream sits in
/// frame — a bench framed on the nozzle photographs the first metre of a six-metre effect.
fn benchAt(v: Verb) rl.Vector3 {
    return if (v == .pour) v3(0, 1.05, combat.RIME_REACH * 0.5) else BENCH_AT;
}

/// A STREAM THAT VARIES: seeded off the ring's own head, which advances with every mote emitted. Seeded off
/// the loop clock instead, every re-fire came out as the same burst replayed.
fn benchRng(st: *const State) mathx.Rng {
    return mathx.Rng.init(@as(u64, st.fxHead) *% 2654435761 +% 0x8BEF);
}

fn benchFire(st: *State) void {
    var rng = benchRng(st);
    switch (st.verb) {
        .gather => elemfx.gather(&st.fx, &st.fxHead, &rng, benchAt(.gather), st.elem, 26, 0.55, 1.0),
        .burst => elemfx.burst(&st.fx, &st.fxHead, &rng, benchAt(.burst), BENCH_DIR, st.elem, 24, 1.0),
        .pour => {}, // a stream is not fired, it runs — see `benchStep`
    }
}

fn benchClear(st: *State) void {
    st.fx = [_]foemod.Particle{.{}} ** BENCH_FX_N;
    st.fxHead = 0;
    st.fxT = 0;
    st.fxAcc = 0;
}

/// One frame of the bench. THROUGH `elemfx` AND `foe.tickParticles`, the same two calls the game makes —
/// a bench with its own integrator would be tuning something the game does not draw.
fn benchStep(st: *State, dt: f32) void {
    st.fxT += dt;
    if (st.verb == .pour) {
        st.fxAcc += dt * elemfx.POUR_RATE;
        var rng = benchRng(st);
        var n: usize = 0;
        while (st.fxAcc >= 1.0 and n < 8) : (n += 1) {
            st.fxAcc -= 1.0;
            elemfx.pour(&st.fx, &st.fxHead, &rng, benchAt(.pour), BENCH_DIR, st.elem, 1, mathx.radians(combat.RIME_ARC), combat.RIME_REACH, 1.0);
        }
        if (n == 8) st.fxAcc = 0;
    } else if (st.fxT >= st.verb.loop()) {
        st.fxT = 0;
        benchFire(st);
    }
    // Floored at 0 — which is most of what says COLD, since it is the one that lies about on the ground.
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
    // …and the particles LAST and unlit, which is where they come in the world's own frame too.
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
        if (ui.chip(ctx, tx, ey, elemfx.elemName(e), st.elem == e, &usedW) and st.elem != e) {
            st.elem = e;
            benchClear(st); // the old element's motes must not hang in the new one's picture
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
    const overView = rl.checkCollisionPointRec(ctx.mouse, viewR);
    const p = &st.fxPose;
    if (overView and ctx.wheel != 0) p.zoom = mathx.clampF(p.zoom * (1.0 + ZOOM_RATE * ctx.wheel), MIN_ZOOM, MAX_ZOOM);
    if (ctx.pressed and overView) st.grabbed = 0;
    if (st.grabbed != null) {
        if (rl.isMouseButtonDown(.left)) {
            const d = rl.getMouseDelta();
            p.yaw += d.x * ROT_RATE;
            p.pitch = mathx.clampF(p.pitch - d.y * ROT_RATE, MIN_PITCH, MAX_PITCH);
        } else st.grabbed = null;
    }

    // THE BENCH RUNS ON THE WALL CLOCK, which is the whole point of it: this is the editor, it is never in
    // `--shot`, and an effect stepped by anything but real time is not the effect being judged.
    benchStep(st, mathx.minF(rl.getFrameTime(), 0.05));
    renderBench(target(&bigRT, BIG_W, BIG_H), env, scene, st);
    blit(bigRT.?, viewR);
    rl.drawRectangleLinesEx(viewR, 1, ui.alpha(ui.TRIM, 110));

    // THE NUMBERS BEING TUNED, beside the thing they make. Every one of them is a field of `elemfx.Sig`.
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
    // The two swatches, drawn rather than printed: a colour is not a number anybody reads.
    inline for (.{ .{ "core", sig.core }, .{ "edge", sig.edge } }) |row| {
        hud.mono(row[0], x, y, hud.MONO, ui.alpha(ui.LABEL, 210));
        rl.drawRectangleRec(ui.rect(x + 56, y + 2, 46, line - 6), row[1]);
        y += line;
    }
    y += 4;
    // …and the two facts that are a YES or a NO rather than a dial, which are half of what tells the four apart.
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
    const count = std.fmt.bufPrintZ(&cb, "{s} {s}   {d} live", .{ elemfx.elemName(st.elem), Verb.label(st.verb), liveParts(st) }) catch "";
    hud.mono(count, box.x + BIG_PAD + 164, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + box.w - 96, by, 80, 24), "Close", hud.MONO, false)) return false;
    return true;
}

/// What is actually in the air — the one number that says whether the pool is big enough for this cell.
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

/// ESC / right-click backs out ONE level: the big viewer to the gallery, the gallery to the map.
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
