const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

// ── EDITOR ICONS ── drawn from primitives, like the HUD's sword and flask, and for the same three
// reasons: the repo ships no image assets and is not about to start for twenty-eight glyphs; a
// drawn icon scales to any button height without a second atlas; and a pack downloaded off the
// internet arrives with a licence, an attribution line and a house style that is not this one.
//
// THEY ARE A SET, and the whole value is in that — an icon strip only builds a visual flow if the
// pieces obviously belong together. So every one is authored on the same notional 16x16 grid,
// scaled by `size`, in ONE colour, at ONE stroke weight, with the same rounded ends. Nothing here
// is filled except where fill IS the meaning (a painted soil swatch, a placed instance).
//
// The rule for reading them: a SHAPE is what the brush lays down (a box, a ring, a line), and DOTS
// are instances. So `scatter` is dots loose in a box, `ring` is dots on a circle, `single` is one
// dot — you can tell the placement brushes apart without reading a word, which is the point.

pub const Icon = enum {
    // layers
    ground,
    cover,
    decor,
    props,
    units,
    // modes + edits
    select,
    erase,
    // cover brushes
    zone,
    clearing,
    // decor brushes
    scatter,
    patch,
    single,
    // prop brushes
    stamp,
    row,
    ring,
    cluster,
    ivy,
    // unit brushes
    toad,
    archer,
    ogre,
    // files
    new,
    open,
    save,
    saveas,
    reload,
    undo,
    redo,
};

/// Draw `ic` centred on (cx, cy), sized to fit a `size`-square box. `col` is the only colour it
/// uses — callers tint by state (hot / active / disabled) exactly as the text beside them does.
pub fn draw(ic: Icon, cx: f32, cy: f32, size: f32, col: rl.Color) void {
    const s = size;
    const w = @max(1.4, s / 11.0); // ONE stroke weight for the whole set, scaled off the box
    const d = dim(col);
    switch (ic) {
        // ── LAYERS ──────────────────────────────────────────────────────────────────────
        // Ground: strata. Three stacked bands, the top one broken — soil you can paint through.
        .ground => {
            hline(cx, cy - s * 0.22, s * 0.72, w, col);
            hline(cx - s * 0.12, cy, s * 0.48, w, col);
            hline(cx + s * 0.22, cy, s * 0.20, w, d);
            hline(cx, cy + s * 0.22, s * 0.72, w, col);
        },
        // Cover: the flora carpet — a bounded field with growth loose inside it. The dashed top
        // edge says the boundary is authored and the contents are not.
        .cover => {
            box(cx, cy, s * 0.78, s * 0.62, w, d);
            var i: i32 = -1;
            while (i <= 1) : (i += 1) {
                const x = cx + @as(f32, @floatFromInt(i)) * s * 0.24;
                vline(x, cy + s * 0.10, s * 0.26, w, col);
                dot(x, cy - s * 0.06, w * 1.1, col);
            }
        },
        // Decor: a fern sprig. TWO frond pairs, not three, and long ones — at 20 px a third pair
        // just fills the gaps in and the whole thing collapses into a blob.
        .decor => {
            line(cx + s * 0.10, cy + s * 0.40, cx - s * 0.04, cy - s * 0.34, w, col); // a leaning stem
            var i: i32 = 0;
            while (i < 2) : (i += 1) {
                const t = 0.30 + @as(f32, @floatFromInt(i)) * 0.36;
                const x = cx + s * (0.10 - 0.14 * t);
                const y = cy + s * (0.40 - 0.74 * t);
                const l = s * (0.34 - @as(f32, @floatFromInt(i)) * 0.09);
                line(x, y, x - l, y - l * 0.62, w, col);
                line(x, y, x + l, y - l * 0.62, w, col);
            }
            dot(cx - s * 0.04, cy - s * 0.34, w * 0.9, col); // the curled tip
        },
        // Props: a column — a WIDE capital and base with a narrow shaft between them. The contrast
        // between those widths is the entire read; at anything less than this it came out as two
        // parallel bars, which is a Roman numeral, not a ruin.
        .props => {
            hline(cx, cy - s * 0.34, s * 0.74, w * 1.3, col); // the abacus, proud of everything
            hline(cx, cy - s * 0.25, s * 0.52, w, col); //      …on its echinus
            vline(cx - s * 0.10, cy + s * 0.02, s * 0.52, w, col);
            vline(cx + s * 0.10, cy + s * 0.02, s * 0.52, w, col);
            hline(cx, cy + s * 0.28, s * 0.52, w, col);
            hline(cx, cy + s * 0.38, s * 0.74, w * 1.3, col); // …and a plinth to match the abacus
        },
        // Units: a figure. Head and shoulders — spawns are people-shaped things.
        .units => {
            ring2(cx, cy - s * 0.20, s * 0.16, w, col);
            arc(cx, cy + s * 0.36, s * 0.30, 180, 360, w, col);
            vline(cx, cy + s * 0.14, s * 0.20, w, col);
        },

        // ── MODES ───────────────────────────────────────────────────────────────────────
        // Select: a pointer. The one icon that is FILLED, because a cursor is a solid thing.
        .select => {
            const p = [_]rl.Vector2{
                .{ .x = cx - s * 0.20, .y = cy - s * 0.36 },
                .{ .x = cx - s * 0.20, .y = cy + s * 0.30 },
                .{ .x = cx - s * 0.03, .y = cy + s * 0.12 },
                .{ .x = cx + s * 0.10, .y = cy + s * 0.40 },
                .{ .x = cx + s * 0.24, .y = cy + s * 0.33 },
                .{ .x = cx + s * 0.11, .y = cy + s * 0.06 },
                .{ .x = cx + s * 0.30, .y = cy + s * 0.02 },
            };
            var i: usize = 0;
            while (i + 1 < p.len) : (i += 1) rl.drawLineEx(p[i], p[i + 1], w, col);
            rl.drawLineEx(p[p.len - 1], p[0], w, col);
        },
        // Erase: an eraser held at an angle, its working end shaded. Not an X — an X means "close"
        // everywhere else in software, and this brush removes rather than dismisses.
        .erase => {
            const a = rl.Vector2{ .x = cx - s * 0.30, .y = cy + s * 0.26 };
            const b = rl.Vector2{ .x = cx + s * 0.18, .y = cy - s * 0.30 };
            rl.drawLineEx(a, b, w * 3.4, d);
            rl.drawLineEx(.{ .x = a.x, .y = a.y }, .{ .x = cx - s * 0.06, .y = cy - s * 0.02 }, w * 3.4, col);
            hline(cx + s * 0.06, cy + s * 0.40, s * 0.62, w, d); // the surface it works on
        },

        // ── COVER BRUSHES ───────────────────────────────────────────────────────────────
        .zone => {
            box(cx, cy, s * 0.68, s * 0.56, w, col);
            // A corner handle, so it reads as a draggable rect and not as a picture frame.
            dot(cx - s * 0.34, cy - s * 0.28, w * 1.5, col);
            dot(cx + s * 0.34, cy + s * 0.28, w * 1.5, col);
        },
        .clearing => {
            ring2(cx, cy, s * 0.34, w, col);
            dot(cx, cy, w * 1.2, col);
        },

        // ── DECOR / PROP BRUSHES ── shape = what is laid down, dots = the instances in it.
        .scatter => {
            box(cx, cy, s * 0.74, s * 0.60, w, d);
            scatterDots(cx, cy, s * 0.28, s * 0.20, w, col, 5);
        },
        .patch => {
            ring2(cx, cy, s * 0.36, w, d);
            scatterDots(cx, cy, s * 0.19, s * 0.19, w, col, 5);
        },
        .single => {
            dot(cx, cy, w * 1.9, col);
            // A crosshair, so "one, exactly there" reads as precision rather than as a full stop.
            hline(cx, cy, s * 0.66, w * 0.8, d);
            vline(cx, cy, s * 0.66, w * 0.8, d);
        },
        .stamp => {
            // A thing coming DOWN onto a surface.
            vline(cx, cy - s * 0.16, s * 0.34, w, col);
            const tip = rl.Vector2{ .x = cx, .y = cy + s * 0.16 };
            rl.drawTriangle(
                .{ .x = tip.x - s * 0.14, .y = tip.y - s * 0.12 },
                .{ .x = tip.x, .y = tip.y + s * 0.10 },
                .{ .x = tip.x + s * 0.14, .y = tip.y - s * 0.12 },
                col,
            );
            hline(cx, cy + s * 0.36, s * 0.66, w, d);
        },
        .row => {
            hline(cx, cy, s * 0.80, w * 0.8, d);
            var i: i32 = -1;
            while (i <= 1) : (i += 1) dot(cx + @as(f32, @floatFromInt(i)) * s * 0.28, cy, w * 1.7, col);
        },
        .ring => {
            ring2(cx, cy, s * 0.34, w * 0.8, d);
            var i: i32 = 0;
            while (i < 7) : (i += 1) {
                if (i == 5) continue; // THE GAP — a ring op leaves one out, and the icon says so
                const a = std.math.tau * @as(f32, @floatFromInt(i)) / 7.0;
                dot(cx + mathx.cosf(a) * s * 0.34, cy + mathx.sinf(a) * s * 0.34, w * 1.5, col);
            }
        },
        // Cluster: a BAND of instances — an annulus, so it reads against `patch` (a filled disc)
        // and `ring` (a single line of them). Six dots at one radius, not eight at three: the
        // scattered version came out as a smudge with a circle round it.
        .cluster => {
            ring2(cx, cy, s * 0.40, w * 0.8, d);
            ring2(cx, cy, s * 0.16, w * 0.8, d);
            var i: i32 = 0;
            while (i < 6) : (i += 1) {
                const a = std.math.tau * @as(f32, @floatFromInt(i)) / 6.0 + 0.5;
                dot(cx + mathx.cosf(a) * s * 0.28, cy + mathx.sinf(a) * s * 0.28, w * 1.5, col);
            }
        },
        // Ivy: leaves climbing a WALL, and the wall is half the meaning — this op only sows on
        // stonework already standing. A fat dim upright on the left says "wall"; three leaves
        // stepping up it on alternating sides say "climber". The old zigzag stem read as a
        // lightning bolt, which is what happens when the connecting line is louder than the leaves.
        .ivy => {
            vline(cx - s * 0.26, cy, s * 0.84, w * 2.6, d); // the wall face
            var i: i32 = 0;
            while (i < 3) : (i += 1) {
                const t = @as(f32, @floatFromInt(i)) / 2.0;
                const y = cy + s * 0.30 - t * s * 0.62;
                const side: f32 = if (@mod(i, 2) == 0) 1.0 else 0.45;
                const x = cx - s * 0.10 + s * 0.22 * side;
                line(cx - s * 0.14, y + s * 0.06, x, y, w, col); // a short stalk off the wall
                dot(x, y, w * 2.0, col); // …and the leaf
            }
            vline(cx - s * 0.14, cy, s * 0.66, w * 0.9, col); // the runner itself, straight up
        },

        // ── UNITS ── three creature silhouettes, told apart at a glance by WIDTH and EYES.
        .toad => {
            arc(cx, cy + s * 0.22, s * 0.38, 180, 360, w, col); // squat and wide
            hline(cx, cy + s * 0.22, s * 0.72, w, col);
            dot(cx - s * 0.15, cy - s * 0.02, w * 1.3, col); // two eyes
            dot(cx + s * 0.15, cy - s * 0.02, w * 1.3, col);
        },
        .archer => {
            arc(cx - s * 0.04, cy, s * 0.34, 300, 420, w, col); // the bow's limb…
            line(cx + s * 0.12, cy - s * 0.29, cx + s * 0.12, cy + s * 0.29, w * 0.7, col); // …its string
            line(cx - s * 0.26, cy, cx + s * 0.30, cy, w * 0.9, col); // …and the nocked shaft
        },
        .ogre => {
            arc(cx, cy + s * 0.28, s * 0.42, 180, 360, w, col); // a great hunched mass
            hline(cx, cy + s * 0.28, s * 0.80, w, col);
            dot(cx, cy - s * 0.04, w * 2.0, col); // ONE eye — the whole character in one dot
        },

        // ── FILES ───────────────────────────────────────────────────────────────────────
        .new => {
            page(cx, cy, s, w, col);
        },
        .open => {
            // A folder opening: back panel, then a front flap kicked out at an angle.
            box(cx, cy - s * 0.02, s * 0.66, s * 0.44, w, d);
            hline(cx - s * 0.16, cy - s * 0.30, s * 0.32, w, col);
            rl.drawLineEx(.{ .x = cx - s * 0.33, .y = cy + s * 0.20 }, .{ .x = cx - s * 0.20, .y = cy + s * 0.36 }, w, col);
            rl.drawLineEx(.{ .x = cx - s * 0.20, .y = cy + s * 0.36 }, .{ .x = cx + s * 0.40, .y = cy + s * 0.36 }, w, col);
            rl.drawLineEx(.{ .x = cx + s * 0.40, .y = cy + s * 0.36 }, .{ .x = cx + s * 0.33, .y = cy + s * 0.20 }, w, col);
        },
        .save => {
            disk(cx, cy, s, w, col, d);
        },
        .saveas => {
            disk(cx - s * 0.06, cy + s * 0.04, s * 0.86, w, col, d);
            // …plus a nib, for "under a new name".
            rl.drawLineEx(.{ .x = cx + s * 0.10, .y = cy - s * 0.12 }, .{ .x = cx + s * 0.40, .y = cy - s * 0.42 }, w * 1.4, col);
            dot(cx + s * 0.42, cy - s * 0.44, w * 1.1, col);
        },
        .reload => {
            // A full circle would read as "loading"; three quarters plus a head reads as an ACT.
            arc(cx, cy, s * 0.32, 40, 330, w, col);
            arrowHead(cx + mathx.cosf(mathx.radians(40)) * s * 0.32, cy + mathx.sinf(mathx.radians(40)) * s * 0.32, s * 0.17, -60, col);
        },
        .undo => {
            arc(cx, cy + s * 0.06, s * 0.30, 180, 360, w, col);
            vline(cx - s * 0.30, cy + s * 0.18, s * 0.24, w, col);
            arrowHead(cx - s * 0.30, cy + s * 0.30, s * 0.17, 90, col);
        },
        .redo => {
            arc(cx, cy + s * 0.06, s * 0.30, 180, 360, w, col);
            vline(cx + s * 0.30, cy + s * 0.18, s * 0.24, w, col);
            arrowHead(cx + s * 0.30, cy + s * 0.30, s * 0.17, 90, col);
        },
    }
}

// ── the primitive kit ───────────────────────────────────────────────────────────────────
// Deliberately tiny. Every icon above is built from these six, which is what keeps the set looking
// like a set: one stroke weight, one cap style, one way of drawing a circle.

/// The set's SECOND value — the same hue at a third of the weight, for the parts of an icon that
/// are context rather than subject (the surface a stamp lands on, the box a scatter fills). Two
/// weights of one colour is what gives a 16 px glyph depth without a second colour to manage.
fn dim(c: rl.Color) rl.Color {
    return rl.Color.init(c.r, c.g, c.b, @intCast(@as(u16, c.a) * 42 / 100));
}

fn line(x0: f32, y0: f32, x1: f32, y1: f32, w: f32, c: rl.Color) void {
    rl.drawLineEx(.{ .x = x0, .y = y0 }, .{ .x = x1, .y = y1 }, w, c);
}
fn hline(cx: f32, cy: f32, len: f32, w: f32, c: rl.Color) void {
    line(cx - len * 0.5, cy, cx + len * 0.5, cy, w, c);
}
fn vline(cx: f32, cy: f32, len: f32, w: f32, c: rl.Color) void {
    line(cx, cy - len * 0.5, cx, cy + len * 0.5, w, c);
}
fn dot(cx: f32, cy: f32, r: f32, c: rl.Color) void {
    rl.drawCircleV(.{ .x = cx, .y = cy }, r, c);
}
fn box(cx: f32, cy: f32, bw: f32, bh: f32, w: f32, c: rl.Color) void {
    rl.drawRectangleLinesEx(.{ .x = cx - bw * 0.5, .y = cy - bh * 0.5, .width = bw, .height = bh }, w, c);
}
/// An outline circle. `drawCircleLines` is a hairline whatever the icon size, so this is drawn as a
/// swept polyline instead — the set has ONE stroke weight and a ring that ignores it stands out.
fn ring2(cx: f32, cy: f32, r: f32, w: f32, c: rl.Color) void {
    arc(cx, cy, r, 0, 360, w, c);
}
fn arc(cx: f32, cy: f32, r: f32, a0: f32, a1: f32, w: f32, c: rl.Color) void {
    const segs: i32 = @intFromFloat(@max(6.0, @abs(a1 - a0) / 18.0));
    var i: i32 = 0;
    while (i < segs) : (i += 1) {
        const t0 = mathx.radians(a0 + (a1 - a0) * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segs)));
        const t1 = mathx.radians(a0 + (a1 - a0) * @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(segs)));
        line(cx + mathx.cosf(t0) * r, cy + mathx.sinf(t0) * r, cx + mathx.cosf(t1) * r, cy + mathx.sinf(t1) * r, w, c);
    }
}
fn arrowHead(cx: f32, cy: f32, r: f32, dirDeg: f32, c: rl.Color) void {
    const a = mathx.radians(dirDeg);
    const tip = rl.Vector2{ .x = cx + mathx.cosf(a) * r, .y = cy + mathx.sinf(a) * r };
    const l = rl.Vector2{ .x = cx + mathx.cosf(a + 2.5) * r, .y = cy + mathx.sinf(a + 2.5) * r };
    const rr = rl.Vector2{ .x = cx + mathx.cosf(a - 2.5) * r, .y = cy + mathx.sinf(a - 2.5) * r };
    // Winding matters: raylib culls a back-facing 2D triangle, so the three go anticlockwise in
    // SCREEN space (y down) or the head simply is not there.
    rl.drawTriangle(tip, l, rr, c);
}
/// Deterministically scattered dots — a fixed seed, so the icon is identical every frame. A
/// re-rolled scatter would shimmer under the cursor, which is the one thing a static glyph must not do.
fn scatterDots(cx: f32, cy: f32, rx: f32, ry: f32, w: f32, c: rl.Color, n: u32) void {
    var rng = mathx.Rng.init(0xC0FFEE);
    var i: u32 = 0;
    while (i < n) : (i += 1) dot(cx + rng.signed() * rx, cy + rng.signed() * ry, w * 1.25, c);
}
fn page(cx: f32, cy: f32, s: f32, w: f32, c: rl.Color) void {
    const x0 = cx - s * 0.26;
    const x1 = cx + s * 0.26;
    const y0 = cy - s * 0.38;
    const y1 = cy + s * 0.38;
    const fold = s * 0.20;
    line(x0, y0, x1 - fold, y0, w, c);
    line(x1 - fold, y0, x1, y0 + fold, w, c); // the corner turned down
    line(x1, y0 + fold, x1, y1, w, c);
    line(x1, y1, x0, y1, w, c);
    line(x0, y1, x0, y0, w, c);
    line(x1 - fold, y0, x1 - fold, y0 + fold, w, c);
    line(x1 - fold, y0 + fold, x1, y0 + fold, w, c);
}
fn disk(cx: f32, cy: f32, s: f32, w: f32, c: rl.Color, d: rl.Color) void {
    box(cx, cy, s * 0.62, s * 0.62, w, c);
    // The shutter at the top and the label at the bottom — the two details that make a square read
    // as a disk rather than as an empty box.
    rl.drawRectangleRec(.{ .x = cx - s * 0.16, .y = cy - s * 0.31, .width = s * 0.32, .height = s * 0.20 }, d);
    box(cx, cy + s * 0.18, s * 0.40, s * 0.22, w * 0.8, c);
}
