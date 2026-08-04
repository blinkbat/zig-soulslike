const std = @import("std");
const rl = @import("raylib");

const envmod = @import("env.zig");
const gfx = @import("gfx.zig");
const hud = @import("hud.zig");
const mathx = @import("mathx.zig");
const props = @import("props.zig");
const ui = @import("ui.zig");

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

// The off-screen targets, at FIXED sizes and shared by every cell: the gallery blits the same texture once per cell, and a fixed size is what keeps a window resize from unloading and reloading a render texture mid-frame (which is a crash, not a hiccup).
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

pub const State = struct {
    shelf: Shelf = .props,
    page: i32 = 0,
    /// The object the big viewer is showing; `null` = the gallery is up.
    open: ?Kind = null,
    /// Per-kind pose, so turning something over and coming back to it later finds it as you left it.
    pose: [props.NK]Pose = [_]Pose{.{}} ** props.NK,
    grabbed: ?usize = null,
    travel: f32 = 0,

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
    // Framed off the kind's HEIGHT as well as its bound.
    const reach = mathx.maxF(mathx.maxF(nfo.top * 0.8, nfo.bound * 0.5), 0.45);
    const fit = reach * FIT / mathx.maxF(mathx.minF(aspect, 1.0), 0.55);
    const dist = fit / mathx.clampF(pose.zoom, MIN_ZOOM, MAX_ZOOM);
    const focus = v3(0, nfo.top * 0.42, 0);
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

fn gallery(st: *State, env: *envmod.Env, scene: *gfx.Scene, ctx: *ui.Ctx) bool {
    const list = st.shelf.kinds();
    const pages = pageCount(list.len);
    st.page = clampI(st.page, 0, pages - 1);
    const box = ui.beginModal(ctx, modalW(), modalH(), "Object viewer");

    var tx = box.x + 16;
    const ty = box.y + 44;
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

    // …and now draw the page: a render/blit pair per cell, so twelve off-screen passes a frame, each one model over a ground quad at 236x198.
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

    const by = box.y + modalH() - 34;
    if (ui.button(ctx, ui.rect(box.x + 16, by, 44, 24), "<", hud.MONO, false)) st.page = @max(0, st.page - 1);
    if (ui.button(ctx, ui.rect(box.x + 64, by, 44, 24), ">", hud.MONO, false)) st.page = @min(pages - 1, st.page + 1);
    var buf: [96]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "page {d}/{d}   {d} objects   drag spins, wheel zooms, click opens", .{ st.page + 1, pages, list.len }) catch "";
    hud.mono(s, box.x + 120, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + modalW() - 96, by, 80, 24), "Close", hud.MONO, false)) return false;
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
    const by = box.y + h - 34;
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD, by, 44, 24), "<", hud.MONO, false)) {
        st.open = list[if (at == 0) list.len - 1 else at - 1];
    }
    if (ui.button(ctx, ui.rect(box.x + BIG_PAD + 48, by, 44, 24), ">", hud.MONO, false)) {
        st.open = list[if (at + 1 >= list.len) 0 else at + 1];
    }
    var cb: [64]u8 = undefined;
    const count = std.fmt.bufPrintZ(&cb, "{d}/{d} in {s}", .{ at + 1, list.len, st.shelf.label() }) catch "";
    hud.mono(count, box.x + BIG_PAD + 104, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + w - 176, by, 74, 24), "Reset", hud.MONO, false)) p.* = .{};
    if (ui.button(ctx, ui.rect(box.x + w - 96, by, 80, 24), "Back", hud.MONO, false)) return false;
    return true;
}


pub fn draw(st: *State, env: *envmod.Env, scene: *gfx.Scene, ctx: *ui.Ctx) bool {
    if (st.open) |k| {
        if (big(st, env, scene, ctx, k)) return true;
        st.open = null;
        st.grabbed = null;
        return true;
    }
    return gallery(st, env, scene, ctx);
}

/// ESC / right-click backs out ONE level: the big viewer to the gallery, the gallery to the map.
pub fn back(st: *State) bool {
    if (st.open == null) return false;
    st.open = null;
    st.grabbed = null;
    return true;
}
