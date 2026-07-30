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

// ── THE OBJECT VIEWER ───────────────────────────────────────────────────────────────────
// A GALLERY of every prop the editor can place — each cell a live 3D thumbnail of the REAL model
// through the REAL scene shader, not an icon — and behind a click, ONE object filling the screen
// that you can turn over and zoom.
//
// It exists to make fixing a model a loop you can run in one place. The alternative was the
// `--shot-props` harness: rebuild, render eighty PNGs, open the one you care about, and see it from
// the single angle the harness chose. Here the offender is three clicks away and you can put the
// light where you need it by turning the thing round.
//
// WHY IT LOOKS RIGHT: the thumbnail is the world's own `Model`, drawn at the origin over the world's
// own ground, with the scene shader bound to the preview camera. Nothing here re-implements the look,
// so a mesh that reads wrong in this viewer reads wrong in the game — which is the entire point of
// having it.
//
// Shelved by LAYER (Decor = the flora palette, Props = everything else), the same split the brush
// palette uses, off the same two comptime lists in props.zig.

/// The layer shelves the gallery offers. The editor's other layers (Ground, Cover, Units) place no
/// props, so there is nothing for this to show them.
pub const Shelf = enum {
    decor,
    props,

    pub fn kinds(s: Shelf) []const Kind {
        return switch (s) {
            .decor => &props.FLORA_KINDS,
            .props => &props.SOLID_KINDS,
        };
    }

    pub fn label(s: Shelf) [:0]const u8 {
        return switch (s) {
            .decor => "Decor",
            .props => "Props",
        };
    }
};

/// One object's view pose. `zoom` is a DOLLY on the framed distance (1 = fit), so it means the same
/// thing for a grass tuft and for a cliff.
const Pose = struct {
    yaw: f32 = BASE_YAW,
    pitch: f32 = BASE_PITCH,
    zoom: f32 = 1.0,
};

// The default three-quarter view, and the pitch rails. Pitch is CLAMPED rather than wrapped: a model
// that flips under itself while you drag is disorienting, and nothing is ever authored to be read
// from underneath.
const BASE_YAW: f32 = 0.62;
const BASE_PITCH: f32 = 0.34;
const MIN_PITCH: f32 = -0.12; // a hair below level — enough to check that a base is planted
const MAX_PITCH: f32 = 1.35;
const MIN_ZOOM: f32 = 0.45;
const MAX_ZOOM: f32 = 4.0;
const ROT_RATE: f32 = 0.008; // radians per pixel of drag
/// Click-vs-drag travel — the SAME threshold the map's right-button gesture uses, so "pressed without
/// moving" means one thing everywhere in the editor.
const CLICK_SLOP = ui.DRAG_PX;
const ZOOM_RATE: f32 = 0.12; // per wheel notch

/// How far back "fit" is, as a multiple of the kind's own bounding radius. Framed off `info.bound`,
/// which is a sphere about the GROUND ORIGIN — so this one number frames a mushroom and a watchtower
/// alike, and a kind whose bound is honest needs no special case here.
const FIT: f32 = 2.05;

/// Preview backdrop: the haze colour the world's own distance fog fades to, so an object sits against
/// the same nothing it sits against out on the plain at range. (Drawing the real `Sky` would want its
/// own fullscreen pass per cell for no gain.)
const BACKDROP = mathx.rgba(52, 48, 40, 255);

// The off-screen targets, at FIXED sizes and shared by every cell: the gallery blits the same texture
// once per cell, and a fixed size is what keeps a window resize from unloading and reloading a render
// texture mid-frame (which is a crash, not a hiccup).
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

/// Free the two targets. The editor never needs this (the viewer lives as long as the window), but a
/// GPU resource with no way to release it is the kind of thing that bites the next feature.
pub fn unload() void {
    if (thumbRT) |t| rl.unloadRenderTexture(t);
    if (bigRT) |t| rl.unloadRenderTexture(t);
    thumbRT = null;
    bigRT = null;
}

/// The viewer's whole state. One instance, on the Editor.
pub const State = struct {
    shelf: Shelf = .props,
    page: i32 = 0,
    /// The object the big viewer is showing; `null` = the gallery is up.
    open: ?Kind = null,
    /// Per-kind pose, so turning something over and coming back to it later finds it as you left it.
    pose: [props.NK]Pose = [_]Pose{.{}} ** props.NK,
    /// The cell a left-drag grabbed (index into the shelf's kind list), and how far it has travelled —
    /// under the slop it is a CLICK (open this object), over it a drag (spin this thumbnail).
    grabbed: ?usize = null,
    travel: f32 = 0,

    pub fn poseOf(self: *State, k: Kind) *Pose {
        return &self.pose[@intFromEnum(k)];
    }

    /// Point the gallery at the shelf that owns `k` and put the big viewer on it — how the properties
    /// panel's "view model" button gets you to the selected op's kind.
    pub fn show(self: *State, k: Kind) void {
        self.shelf = if (props.info(k).flora) .decor else .props;
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

// ── framing ─────────────────────────────────────────────────────────────────────────────

/// The camera for one preview: orbit the object at the distance that FITS it, then let the pose dolly
/// in. Target rides a little under half the mesh's height, which is what centres a tower without
/// burying a ground-hugger at the bottom of the frame.
fn camFor(nfo: *const props.Info, pose: Pose, aspect: f32) rl.Camera3D {
    // Framed off the kind's HEIGHT as well as its bound. `info.bound` is deliberately generous (a
    // too-small one pops geometry at the frustum edge, so every row rounds up), and framing off it
    // alone left a grass tuft as a speck in the middle of an empty field.
    const reach = mathx.maxF(mathx.maxF(nfo.top * 0.8, nfo.bound * 0.5), 0.45);
    // A WIDE object needs the horizontal room, and at a 16:9 aspect the vertical FOV is the binding
    // one — so the fit distance is taken against the tighter of the two.
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

/// Render one object into `rt`. The scene shader is left pointed at this camera; the next frame's
/// world pass rebinds it, which is why nothing here has to put it back.
fn render(rt: rl.RenderTexture2D, env: *envmod.Env, scene: *gfx.Scene, kind: Kind, pose: Pose) void {
    const nfo = props.info(kind);
    const aspect = @as(f32, @floatFromInt(rt.texture.width)) / @as(f32, @floatFromInt(rt.texture.height));
    const cam = camFor(nfo, pose, aspect);
    rl.beginTextureMode(rt);
    rl.clearBackground(BACKDROP);
    rl.beginMode3D(cam);
    scene.bind(cam.position);
    // NO CAST SHADOWS: a preview runs no depth pass of its own, so left as it is every fragment
    // would be tested against the WORLD's shadow map through the world's light matrix — the object
    // coming back arbitrarily dark depending on where the hero happens to be standing.
    scene.shadowsOff();
    scene.setLights(&.{}); // …and no torches: a preview is lit by the sun and the sky, like a field
    scene.setGround(true);
    env.drawGround();
    scene.setGround(false);
    // FLORA SWAYS in the world, so it sways here — a fern judged rigid is a fern judged wrong.
    scene.setWind(nfo.flora);
    rl.drawModel(env.model(kind), mathx.zero3, 1.0, rl.Color.white);
    scene.setWind(false);
    rl.endMode3D();
    rl.endTextureMode();
}

/// Blit a render target into a screen rect, upright (the negative source height is the flip) and
/// scaled to fit whatever the layout gave us.
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

// ── the gallery ─────────────────────────────────────────────────────────────────────────

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

/// One row pitch for the readout column — THE editor's, not a private one off the same font metric.
/// It was `monoLineH + 4` against the panels' `+ 6`, which is exactly the drift editor.zig's own
/// ROW_H comment exists to stop; both now read `ui.ROW_H`.
fn lineH() i32 {
    return ui.ROW_H;
}

const clampI = mathx.clampI; // the shared one — this file used to carry its own copy

/// Draw + drive the GALLERY. Returns true while the viewer should stay up.
fn gallery(st: *State, env: *envmod.Env, scene: *gfx.Scene, ctx: *ui.Ctx) bool {
    const list = st.shelf.kinds();
    const pages = pageCount(list.len);
    st.page = clampI(st.page, 0, pages - 1);
    const box = ui.beginModal(ctx, modalW(), modalH(), "Object viewer");

    // SHELF TABS. Same chips the brush palette uses, so the two read as one editor.
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

    // Which cell is the pointer over? Needed before the wheel is spent: over a cell it zooms THAT
    // object, anywhere else it pages.
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

    // GRAB → DRAG SPINS, RELEASE WITHOUT TRAVEL OPENS. One gesture, and which one it was is decided
    // by how far the pointer moved: an editor where you cannot spin a thumbnail in place is missing
    // the point, and one where every spin also opens a modal is unusable.
    if (ctx.pressed) {
        st.grabbed = hover;
        st.travel = 0;
    }
    // BOUNDS-CHECKED ON BOTH ARMS. `grabbed` is an index into the SHELF's kind list, and the shelf
    // is a different length per shelf — so a grab that outlives a shelf change indexes off the end
    // of the shorter one and reads a `Kind` out of range. The release arm already guarded; the drag
    // arm did not, and one guard is a guard nobody can rely on.
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

    // …and now draw the page: a render/blit pair per cell, so twelve off-screen passes a frame, each one
    // model over a ground quad at 236x198. That is ~0.5 Mpx of the scene shader against the ~1 Mpx the
    // world behind it already costs, and it is only paid while the gallery is actually open — so it is
    // left alone rather than cached. (Not measured with a profiler; that is the arithmetic.)
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

    // FOOTER: paging, the count, and the two gestures spelled out. A viewer whose controls you have
    // to guess is a viewer you use once.
    const by = box.y + modalH() - 34;
    if (ui.button(ctx, ui.rect(box.x + 16, by, 44, 24), "<", hud.MONO, false)) st.page = @max(0, st.page - 1);
    if (ui.button(ctx, ui.rect(box.x + 64, by, 44, 24), ">", hud.MONO, false)) st.page = @min(pages - 1, st.page + 1);
    var buf: [96]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, "page {d}/{d}   {d} objects   drag spins, wheel zooms, click opens", .{ st.page + 1, pages, list.len }) catch "";
    hud.mono(s, box.x + 120, by + 5, hud.MONO, ui.alpha(ui.LABEL, 210));
    if (ui.button(ctx, ui.rect(box.x + modalW() - 96, by, 80, 24), "Close", hud.MONO, false)) return false;
    return true;
}

// ── the big viewer ──────────────────────────────────────────────────────────────────────

const BIG_PAD: i32 = 16;
const INFO_W: i32 = 250; // the readout column beside the object

/// Draw + drive the SINGLE-OBJECT viewer. Returns false when it should close back to the gallery.
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

    // Wheel zooms and drag spins ANYWHERE over the view — the whole panel is the object here, so
    // there is nothing else in it to compete for the gesture.
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

    // THE INFO COLUMN — every number the engine actually reads off this kind. Half of "why does this
    // prop look wrong" is a row in INFO disagreeing with the mesh (a bound that clips it at the frame
    // edge, a top that cuts its shadow short, a footprint you bump into a metre from the trunk), and
    // none of that is visible in the model itself.
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
    // ASCII only in the readout: the editor's system monospace face has no middle dot, and a missing
    // glyph draws as a question mark — which reads as a bug in the number beside it.
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

    // Walking the shelf from HERE is the fix-a-prop loop: judge one, step to the next, no round trip
    // through the gallery.
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

// ── the one entry point ─────────────────────────────────────────────────────────────────

/// Draw whichever of the two is up, and drive it. Returns false when the viewer has been dismissed
/// (the editor closes the modal on that). ESC is the editor's own back-out and is handled there, so
/// this only reports its buttons.
pub fn draw(st: *State, env: *envmod.Env, scene: *gfx.Scene, ctx: *ui.Ctx) bool {
    if (st.open) |k| {
        if (big(st, env, scene, ctx, k)) return true;
        // Out of the big viewer and back to the gallery, which is a level of "back" of its own —
        // dismissing straight to the map would lose the shelf and page you were working through.
        st.open = null;
        st.grabbed = null;
        return true;
    }
    return gallery(st, env, scene, ctx);
}

/// ESC / right-click backs out ONE level: the big viewer to the gallery, the gallery to the map.
/// Returns false once there is nothing left to back out of.
pub fn back(st: *State) bool {
    if (st.open == null) return false;
    st.open = null;
    st.grabbed = null;
    return true;
}
