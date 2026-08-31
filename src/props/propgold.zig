const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// **THE GILDED RUINS** (owner's brief: golden ruins, Arabic influence, shiny gold, Moebius, FromSoft, on the
// ASH). Sunbleached limestone gold-leafed and then burned. The gold is `Mat.gilt` — its own shader branch,
// warm on both hotspot and rim, because gold under steel's cool fresnel comes back blued silver.
//
// **THE GOLD IS A SKIN AND THE SKIN HAS COME OFF.** Every piece is masonry FIRST, gilded second, and the
// gilding is authored as MISSING in patches. A fully gilt object is a gold prop; a half-gilt one is a ruin
// that used to be gold.
//
// **THE FORMS ARE ARABIC**: the horseshoe arch carrying past its own semicircle, muqarnas for every capital
// and corbel, an eight-point star for every plan, a pierced jali screen, a ribbed melon dome, an octagonal
// minaret. No Gothic pointed arch, no classical column, nothing symmetrical.
//
// `props.biome` files the family under `.ash`, which RECORDS that and does not act on it: nothing sows off
// that table, so the pieces go down by hand.

// **SOLVE IT, DO NOT GUESS IT** (AGENTS.md): screen = 255 x (albedo x 1.72)^(1/2.2). MEASURED through that
// chain, `propart.DRIFT` lands at 161 and ordinary `STONE` at 168, so an "off-white" authored by eye comes up
// the same value as the ground. Wanted ~1.15x the drift, i.e. 188: (188/255)^2.2 = 0.510, / 1.72 = 0.297 -> 76.
pub const ASHLAR = rgba(76, 70, 58, 255);
pub const ASHLAR_LT = rgba(92, 85, 70, 255);
pub const ASHLAR_DK = rgba(54, 50, 42, 255);
/// The SAME stone with the fire's mark on it, not a third stone. Solved to 126, half the ashlar's screen value.
pub const SCORCH = rgba(30, 27, 23, 255);
/// Leaf over stone, solved to 178 — a hair UNDER the ashlar in diffuse, because `Mat.gilt` puts a 2.4 hotspot and a warm rim on top of it and a bright base under that is a flat lemon.
pub const GOLD = rgba(67, 47, 17, 255);
pub const GOLD_LT = rgba(86, 62, 24, 255);
/// The tarnish authored in the MESH as well as the shader, so a piece reads worn from across the field and not only up close.
pub const GOLD_DK = rgba(38, 30, 14, 255);

/// **EVERY ARCH IN THE FAMILY IS A HORSESHOE**: it carries PAST the semicircle and tucks back in under itself. Degrees each side beyond 180 — at 0 this is a Roman arch.
const HORSE_EXTRA: f32 = 32.0;

/// Tiers, and how far each steps out over the one below as a share of its own width.
const MUQ_TIERS: i32 = 4;
// Share of the whole rise each tier hangs out past the one below. At 0.34 the top tier cantilevered a metre off a metre-high corbel. Real ones project under half.
const MUQ_STEP: f32 = 0.15;
comptime {
    // `muqarnasInto` widens each tier over `MUQ_TIERS - 1`; at one tier that is a divide by zero.
    std.debug.assert(MUQ_TIERS > 1);
}

/// **THE FAMILY'S PLAN IS AN OCTAGON.** One number: two meshes each declaring `SIDES = 8` is two chances for a nine-sided minaret on an eight-sided plinth.
const OCTAGON: i32 = 8;

/// Sides on a NICHE, the one shape here sown by the dozen: a column carries four corbels of fourteen hollows
/// and `addDome` spends `sides * 3` triangles on each. At 8 that is 2,688 triangles of niche on one column; at
/// 6 it is 2,016, and the difference is invisible on a hollow 0.34 m across at the 320 m the kind is drawn to.
const NICHE_SIDES: i32 = 6;

fn ashlarTone(r: *mathx.Rng) rl.Color {
    const f = r.float();
    if (f < 0.16) return ASHLAR_LT;
    if (f < 0.34) return ASHLAR_DK;
    if (f < 0.42) return SCORCH;
    return ASHLAR;
}

fn goldTone(r: *mathx.Rng) rl.Color {
    const f = r.float();
    if (f < 0.30) return GOLD_LT;
    if (f < 0.52) return GOLD_DK;
    return GOLD;
}

/// **THE HONEYCOMB, ONE CORBEL OF IT** — and it must CORBEL, every tier hanging further out over the one
/// below. Built the other way (cells sunk into a mass) the whole form vanishes: the block shipped once as a
/// plain white box because its honeycomb was authored INSIDE its own footprint.
///
/// `face` is the outward direction in XZ. Tier 0 sits at the wall and each one above steps `MUQ_STEP` of the
/// rise further out. The niche MOUTHS are gilt and the cell walls stone: that contrast is what reads as depth.
fn muqarnasInto(b: *Builder, r: *mathx.Rng, c: rl.Vector3, face: rl.Vector3, w: f32, up: f32, gild: f32) void {
    const th = up / @as(f32, @floatFromInt(MUQ_TIERS));
    const f = mathx.normV(v3(face.x, 0, face.z));
    const s = v3(-f.z, 0, f.x);
    var t: i32 = 0;
    while (t < MUQ_TIERS) : (t += 1) {
        const ft = @as(f32, @floatFromInt(t));
        const y = c.y + th * (ft + 0.5);
        const grow = 0.58 + 0.42 * ft / @as(f32, @floatFromInt(MUQ_TIERS - 1));
        const half = w * 0.5 * grow;
        const out = MUQ_STEP * up * ft;
        // **THE SHELF IS ONE PIECE AND THE NICHES HANG UNDER IT.** One box per cell and the cells met their
        // neighbours, so every tier came back a solid bar: what reads as a honeycomb is the ROW OF HOLLOWS under a lip.
        const depth = th * 1.05;
        b.setMat(.stone);
        b.addBox(
            v3(c.x + f.x * (out + depth * 0.5), y + th * 0.30, c.z + f.z * (out + depth * 0.5)),
            v3(s.x * half, r.signed() * 0.004, s.z * half),
            v3(0, th * 0.20, 0),
            v3(f.x * depth * 0.5, 0, f.z * depth * 0.5),
            if (r.float() < 0.22) ASHLAR_LT else ASHLAR,
        );
        const cells: i32 = 2 + t;
        var i: i32 = 0;
        while (i < cells) : (i += 1) {
            const u = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(cells));
            const off = (u - 0.5) * half * 2.0;
            const pitch = half * 2.0 / @as(f32, @floatFromInt(cells));
            // A third of the pitch, so two thirds of the tier is hollow.
            const cx = c.x + s.x * (off + pitch * 0.5) + f.x * (out + depth * 0.42);
            const cz = c.z + s.z * (off + pitch * 0.5) + f.z * (out + depth * 0.42);
            if (i + 1 < cells) {
                b.addBox(
                    v3(cx, y - th * 0.12, cz),
                    v3(s.x * pitch * 0.16, 0, s.z * pitch * 0.16),
                    v3(0, th * 0.36, 0),
                    v3(f.x * depth * 0.40, 0, f.z * depth * 0.40),
                    ashlarTone(r),
                );
            }
            // Set BACK behind the shelf's lip, so it is a shadowed niche and never a proud bead (RELIEF IS SUBTLE).
            const nx = c.x + s.x * off + f.x * (out + depth * 0.12);
            const nz = c.z + s.z * off + f.z * (out + depth * 0.12);
            const nr = @min(pitch * 0.40, th * 0.42);
            // ONE DRAW, not two: rolled separately for the material and the colour, a fifth of the niches came out gilt-shaded and scorch-coloured.
            const leaf = r.float() < gild;
            b.setMat(if (leaf) .gilt else .stone);
            b.addDome(
                v3(nx, y - th * 0.06, nz),
                f,
                nr,
                NICHE_SIDES,
                if (leaf) goldTone(r) else SCORCH,
            );
        }
    }
}

/// A band of gilt round a RECTANGULAR mass — four thin plates with the corners left open, so it reads as leaf
/// on stone and not as a gold ring.
///
/// **IT TAKES BOTH HALF-EXTENTS AND IT HAS TO.** Given one it was a square band, and three of its callers are
/// not square: on a 0.34 m wall its cross-plates stood 0.68 m out either side as gold planks in mid-air. Round masses take `giltRingInto`.
fn giltBandInto(b: *Builder, r: *mathx.Rng, cx: f32, y: f32, cz: f32, halfX: f32, halfZ: f32, h: f32) void {
    b.setMat(.gilt);
    for ([_][2]f32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |s| {
        if (r.float() < 0.22) continue; // A COURSE OF IT IS ALWAYS GONE
        // The plate runs ALONG the face it is on, so its length comes off the other axis' half-extent.
        const along = v3(s[1] * halfX * 0.92, 0, s[0] * halfZ * 0.92);
        b.addBox(
            v3(cx + s[0] * halfX, y + r.signed() * 0.01, cz + s[1] * halfZ),
            along,
            v3(0, h * 0.5, 0),
            v3(s[0] * 0.022, 0, s[1] * 0.022),
            goldTone(r),
        );
    }
}

/// …and the same frieze round a ROUND or POLYGONAL one. Plates laid tangentially with gaps: a four-plate square band on a 0.40 m column hangs its corners 0.16 m out in the air.
fn giltRingInto(b: *Builder, r: *mathx.Rng, cx: f32, y: f32, cz: f32, radius: f32, h: f32, sides: i32) void {
    b.setMat(.gilt);
    const n: f32 = @floatFromInt(sides);
    var i: i32 = 0;
    while (i < sides) : (i += 1) {
        if (r.float() < 0.22) continue;
        const a = std.math.tau * (@as(f32, @floatFromInt(i)) + 0.5) / n;
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        // Half the chord, so consecutive plates all but meet and the gaps read as lost leaf.
        const half = std.math.tau * radius / n * 0.46;
        b.addBox(
            v3(cx + ca * radius, y + r.signed() * 0.01, cz + sa * radius),
            v3(-sa * half, 0, ca * half),
            v3(0, h * 0.5, 0),
            v3(ca * 0.026, 0, sa * 0.026),
            goldTone(r),
        );
    }
}

/// The eight-point star (khatim) — two squares at 45 degrees. Laid FLAT as a plan for basins and paving.
fn starInto(b: *Builder, r: *mathx.Rng, c: rl.Vector3, out: f32, h: f32, col: rl.Color) void {
    for ([_]f32{ 0, 45.0 }) |deg| {
        const a = mathx.radians(deg);
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        b.addBox(
            c,
            v3(ca * out, 0, sa * out),
            v3(0, h * 0.5, 0),
            v3(-sa * out, 0, ca * out),
            if (r.float() < 0.3) ASHLAR_DK else col,
        );
    }
}

// THE GATE ARCH. A horseshoe on two piers with the crown broken out on one side, and you go THROUGH it (`props` gives it two foot colliders and the gap between them).

pub const ARCH_HALF: f32 = 2.35;
pub const ARCH_SPRING: f32 = 3.10;
pub const ARCH_R: f32 = 2.35;
pub const ARCH_TOP: f32 = ARCH_SPRING + ARCH_R + 1.05;

// **MARBLE, AND IT IS NOT `propart.MARBLE`** — that one comes back at 160 screen, DARKER than this family's own
// ashlar at 188, which makes marble in a gilded city read as the dirty stone. Solved through the same chain
// (`albedo = screen^2.2 / 1.72`): body 208 -> 95, lit 222 -> 109, break 168 -> 59.
pub const MARBLE = rgba(95, 93, 88, 255);
pub const MARBLE_LT = rgba(109, 107, 101, 255);
/// The inside of a break, where marble is DARKEST: a fresh fracture is in shadow all day.
pub const MARBLE_DK = rgba(59, 57, 54, 255);
/// **THE VEINING IS COOL AND EVERYTHING ELSE HERE IS WARM.** Solved to 132, and separated on HUE from the
/// ashlar as much as on value (AGENTS.md) — grey-blue against a warm limestone gold.
pub const VEIN = rgba(32, 35, 40, 255);

fn marbleTone(r: *mathx.Rng) rl.Color {
    const f = r.float();
    if (f < 0.22) return MARBLE_LT;
    if (f < 0.36) return MARBLE_DK;
    return MARBLE;
}

/// One vein across a flag or a face. **A CAPSULE AND NOT A SECOND FLAG**: geometry the flag's own size is a
/// stripe, and a stripe is a painted line. Sunk `depth` in so only its crown shows (the relief law).
fn veinAcross(b: *Builder, r: *mathx.Rng, c: rl.Vector3, half: f32, y: f32, depth: f32) void {
    const a = r.angle();
    const d = v3(mathx.cosf(a), 0, mathx.sinf(a));
    const kink = r.range(0.18, 0.46);
    const mid = v3(c.x + d.z * kink * half, y - depth, c.z - d.x * kink * half);
    const w = half * r.range(0.028, 0.055);
    b.addCapsule(v3(c.x - d.x * half, y - depth, c.z - d.z * half), mid, w, w * 0.8, 5, VEIN);
    b.addCapsule(mid, v3(c.x + d.x * half, y - depth, c.z + d.z * half), w * 0.8, w * 0.55, 5, VEIN);
}

/// **THIS FAMILY'S THESIS AS AN OBJECT** — the note at the top of the file: the gold is a skin and the skin has
/// come off. Ankle-high, so no collider; it still casts, because a 0.3 m mass with no shadow is a decal.
pub const LEAF_R: f32 = 1.30;
pub const LEAF_TOP: f32 = 0.34;
pub fn giltLeafMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x601D);
    b.setMat(.stone);
    b.addBlob(v3(0, 0.020, 0), v3(LEAF_R * 0.86, 0.036, LEAF_R * 0.72), 3, 11, ASHLAR_DK);
    b.setMat(.gilt);
    // **CURLED, NEVER FLAT** — a flat quad of leaf is a sticker; the ROLL at one edge is what says thin metal.
    var i: i32 = 0;
    while (i < 14) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.06, 0.94) * LEAF_R;
        const cx = mathx.cosf(a) * d;
        const cz = mathx.sinf(a) * d * 0.82;
        const yaw = rng.angle();
        const half = rng.range(0.10, 0.27);
        const rise = rng.range(0.012, 0.055);
        const lift = rng.range(0.030, 0.185);
        const u = v3(mathx.cosf(yaw), 0, mathx.sinf(yaw));
        const w = v3(-u.z, 0, u.x);
        const tone = goldTone(&rng);
        b.addBox(
            v3(cx, lift, cz),
            v3(u.x * half, rng.signed() * 0.02, u.z * half),
            v3(0, rise, 0),
            v3(w.x * half * rng.range(0.42, 0.86), rng.signed() * 0.03, w.z * half * rng.range(0.42, 0.86)),
            tone,
        );
        // On ONE side only, whichever way the sheet lifted.
        const side: f32 = if (rng.float() < 0.5) 1.0 else -1.0;
        b.addCapsule(
            v3(cx - u.x * half + w.x * side * half * 0.5, lift + rise * 1.1, cz - u.z * half + w.z * side * half * 0.5),
            v3(cx + u.x * half + w.x * side * half * 0.62, lift + rise * 1.5, cz + u.z * half + w.z * side * half * 0.62),
            rng.range(0.014, 0.030),
            rng.range(0.010, 0.022),
            5,
            if (rng.float() < 0.4) GOLD_LT else tone,
        );
    }
    var f: i32 = 0;
    while (f < 22) : (f += 1) {
        const a = rng.angle();
        const d = rng.range(0.2, 1.15) * LEAF_R;
        const rr = rng.range(0.014, 0.040);
        b.addBlob(v3(mathx.cosf(a) * d, rng.range(0.024, 0.070), mathx.sinf(a) * d * 0.8), v3(rr, rr * 0.30, rr), 2, 6, goldTone(&rng));
    }
    return b.toModel(shader);
}

/// **FLAGS WITH GAPS, NOT A SLAB WITH LINES ON IT.** Each flag has its own height and its own hair of yaw, so
/// the joints are real geometry. Walked over: no collider, and `casts = false` — paving shadow on paving is mud.
pub const FLOOR_R: f32 = 2.60;
pub fn marbleFloorMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x601E);
    b.setMat(.stone);
    // THE BED under the flags — without it the joints leak sky (the packed-stone law).
    b.addBox(v3(0, -0.055, 0), v3(FLOOR_R * 0.98, 0, 0), v3(0, 0.055, 0), v3(0, 0, FLOOR_R * 0.94), ASHLAR_DK);
    const grid = 4;
    var ix: i32 = 0;
    while (ix < grid) : (ix += 1) {
        var iz: i32 = 0;
        while (iz < grid) : (iz += 1) {
            // A quarter GONE: a floor with every flag in it was never walked on.
            if (rng.float() < 0.24) continue;
            const ux = (@as(f32, @floatFromInt(ix)) + 0.5) / grid * 2.0 - 1.0;
            const uz = (@as(f32, @floatFromInt(iz)) + 0.5) / grid * 2.0 - 1.0;
            const pitch = FLOOR_R * 2.0 / grid;
            const half = pitch * 0.5 * rng.range(0.80, 0.94);
            const cx = ux * FLOOR_R + rng.signed() * 0.05;
            const cz = uz * FLOOR_R + rng.signed() * 0.05;
            const y = rng.range(0.004, 0.048);
            const yaw = rng.signed() * 0.10;
            const u = v3(mathx.cosf(yaw), 0, mathx.sinf(yaw));
            const w = v3(-u.z, 0, u.x);
            b.addBox(
                v3(cx, y * 0.5, cz),
                v3(u.x * half, rng.signed() * 0.008, u.z * half),
                v3(0, y * 0.5 + 0.010, 0),
                v3(w.x * half, rng.signed() * 0.008, w.z * half),
                marbleTone(&rng),
            );
            if (rng.float() < 0.55) veinAcross(&b, &rng, v3(cx, 0, cz), half * 0.92, y + 0.006, 0.004);
        }
    }
    return b.toModel(shader);
}

/// Two pieces parted along one crack, the smaller tipped off the line: a single tidy box is a crate.
pub const SLAB_TOP: f32 = 1.05;
pub fn marbleSlabMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x601F);
    b.setMat(.stone);
    const L: f32 = 1.62;
    const W: f32 = 0.78;
    const Hh: f32 = 0.46;
    const lean = rng.range(0.03, 0.09);
    b.addBox(
        v3(-0.16, Hh * 0.52, 0),
        v3(L * 0.62, lean, rng.signed() * 0.04),
        v3(-lean * L, Hh * 0.52, 0),
        v3(0, rng.signed() * 0.03, W * 0.5),
        MARBLE,
    );
    // Tipped up on the greater's shoulder: this is the whole silhouette.
    const tip = rng.range(0.20, 0.34);
    b.addBox(
        v3(L * 0.52, Hh * 0.86, rng.signed() * 0.10),
        v3(L * 0.34, tip, rng.signed() * 0.05),
        v3(-tip * L * 0.5, Hh * 0.42, 0),
        v3(0, 0, W * 0.42),
        MARBLE_LT,
    );
    // The break face: the one thing that says stone and not a casting.
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const t = (@as(f32, @floatFromInt(i)) + 0.5) / 7.0;
        const rr = rng.range(0.045, 0.105);
        b.addBlob(
            v3(L * 0.30 + rng.signed() * 0.05, Hh * (0.24 + 0.72 * t), (t - 0.5) * W * 0.88),
            v3(rr * 0.7, rr, rr),
            3,
            7,
            MARBLE_DK,
        );
    }
    veinAcross(&b, &rng, v3(-0.16, 0, 0), L * 0.55, Hh * 1.04, 0.010);
    veinAcross(&b, &rng, v3(L * 0.50, 0, 0), L * 0.28, Hh * 1.28, 0.008);
    veinAcross(&b, &rng, v3(L * 0.55, 0, 0), L * 0.20, Hh * 1.30, 0.007);
    // Centuries on the turf: soil splash low on the flanks, moss at the ground line.
    var sb: i32 = 0;
    while (sb < 3) : (sb += 1) {
        const side: f32 = if (sb == 2) -1 else 1;
        const bx = rng.range(-0.85, 0.55);
        const bw = rng.range(0.14, 0.30);
        b.addBox(
            v3(bx, rng.range(0.03, 0.06), side * (W * 0.5 + 0.004)),
            v3(bw, rng.signed() * 0.01, 0),
            v3(0, rng.range(0.030, 0.048), 0),
            v3(0, 0, 0.012),
            MARBLE_DK,
        );
        b.addBox(
            v3(bx + rng.signed() * bw, rng.range(0.05, 0.09), side * (W * 0.5 + 0.003)),
            v3(bw * rng.range(0.45, 0.70), rng.signed() * 0.008, 0),
            v3(0, rng.range(0.020, 0.035), 0),
            v3(0, 0, 0.011),
            MARBLE_DK,
        );
    }
    b.setMat(.plant);
    art.lichenInto(&b, &rng, v3(-0.35, 0.06, rng.range(0.28, 0.36)), v3(0.42, 0.05, 0.10), 4);
    art.lichenInto(&b, &rng, v3(-L * 0.68, 0.08, -0.08), v3(0.12, 0.07, 0.18), 3);
    // It was gilt once.
    b.setMat(.gilt);
    b.addBox(
        v3(rng.range(-0.5, 0.2), Hh * 1.05, rng.signed() * 0.18),
        v3(rng.range(0.16, 0.34), 0.004, 0),
        v3(0, 0.008, 0),
        v3(0, 0.003, rng.range(0.08, 0.19)),
        GOLD_DK,
    );
    return b.toModel(shader);
}

/// **A FLIGHT THAT ARRIVES NOWHERE** — the top treads carried away, so the run stops in mid-air, which is the
/// only thing separating a ruin's stair from a building's. The risers are the ashlar core showing through.
pub const STAIR_RISE: f32 = 0.26;
pub const STAIR_N: i32 = 6;
pub const STAIR_TOP: f32 = STAIR_RISE * @as(f32, @floatFromInt(STAIR_N));
pub const STAIR_W: f32 = 2.05;
pub fn marbleStairMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x6010);
    // **THE TREADS OVERLAP THEIR RISERS OR IT IS NOT A STAIR.** With a gap between each tread and its core, six
    // steps read as six crates: a run reads as a run because each nosing HANGS OVER the riser below.
    const tread: f32 = 0.52;
    var i: i32 = 0;
    while (i < STAIR_N) : (i += 1) {
        const fi = @as(f32, @floatFromInt(i));
        const y = STAIR_RISE * fi;
        // Only the top TWO, and only their ends: a flight that narrows all the way up is a ziggurat.
        const gone = if (i >= STAIR_N - 2) rng.range(0.20, 0.44) else 0;
        const half = STAIR_W * 0.5 * (1.0 - gone);
        const off = if (gone > 0) rng.signed() * STAIR_W * 0.10 else 0;
        // From the ground up, so no joint can leak sky (the packed-stone law).
        b.setMat(.stone);
        b.addBox(
            v3(off, (y + STAIR_RISE) * 0.5, -fi * tread),
            v3(half * 1.01, 0, 0),
            v3(0, (y + STAIR_RISE) * 0.5, 0),
            v3(0, 0, tread * 0.52),
            ashlarTone(&rng),
        );
        // NOSING OUT past the riser by a fifth of its own depth.
        b.addBox(
            v3(off + rng.signed() * 0.015, y + STAIR_RISE + 0.022, -fi * tread + tread * 0.14),
            v3(half * rng.range(0.96, 1.00), rng.signed() * 0.005, 0),
            v3(0, 0.024, 0),
            v3(0, rng.signed() * 0.005, tread * 0.66),
            marbleTone(&rng),
        );
        if (rng.float() < 0.6) veinAcross(&b, &rng, v3(off, 0, -fi * tread + tread * 0.14), half * 0.66, y + STAIR_RISE + 0.044, 0.006);
    }
    // THE CHEEKS: what stops the flight reading as a stack of slabs end-on. Broken at different heights.
    b.setMat(.stone);
    for ([_]f32{ -1.0, 1.0 }) |side| {
        const upto = rng.range(0.55, 0.80);
        const n = @as(i32, @intFromFloat(@floor(@as(f32, @floatFromInt(STAIR_N)) * upto)));
        var k: i32 = 0;
        while (k < n) : (k += 1) {
            const fk = @as(f32, @floatFromInt(k));
            const h = STAIR_RISE * (fk + 1.0) + 0.30;
            b.addBox(
                v3(side * (STAIR_W * 0.5 + 0.16), h * 0.5, -fk * tread),
                v3(0.15, 0, 0),
                v3(0, h * 0.5, 0),
                v3(0, 0, tread * 0.52),
                if (rng.float() < 0.3) ASHLAR_LT else ASHLAR,
            );
        }
    }
    b.setMat(.stone);
    var j: i32 = 0;
    while (j < 6) : (j += 1) {
        const rr = rng.range(0.07, 0.17);
        b.addBlob(
            v3(rng.signed() * STAIR_W * 0.6, rr * 0.7, rng.range(0.35, 1.25)),
            v3(rr, rr * 0.7, rr * rng.range(0.8, 1.3)),
            3,
            7,
            if (rng.float() < 0.5) MARBLE_DK else ASHLAR_DK,
        );
    }
    return b.toModel(shader);
}

pub fn giltArchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x60_1D_A1);

    for ([_]f32{ -ARCH_HALF, ARCH_HALF }) |x| {
        b.setMat(.stone);
        b.addBox(v3(x, 0.20, 0), v3(0.86, rng.signed() * 0.014, 0.02), v3(rng.signed() * 0.02, 0.20, 0), v3(0.02, 0, 0.86), ASHLAR_DK);
        _ = art.courseStack(&b, &rng, x, 0.38, 0, 1.10, 1.02, 0.40, 7, 0.06);
        giltBandInto(&b, &rng, x, 1.34, 0, 0.56, 0.52, 0.13);
        muqarnasInto(&b, &rng, v3(x, ARCH_SPRING - 0.74, 0), v3(if (x < 0) 1 else -1, 0, 0), 1.00, 0.74, 0.72);
    }

    // The ring runs from -EXTRA to 180+EXTRA, so both ends tuck back INSIDE the piers — that overhang is the silhouette the whole form is for.
    const span = 180.0 + HORSE_EXTRA * 2.0;
    const NV: i32 = 21;
    const gone0: i32 = 12;
    const gone1: i32 = 14;
    var i: i32 = 0;
    while (i < NV) : (i += 1) {
        if (i >= gone0 and i <= gone1) continue;
        const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, NV);
        const a = mathx.radians(-HORSE_EXTRA + span * t);
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        const half = mathx.radians(span) * ARCH_R / @as(f32, NV) * 0.5 * rng.range(1.04, 1.18);
        const key = i == NV / 2;
        const rad = 0.40 * (if (key) @as(f32, 1.26) else rng.range(0.92, 1.06));
        const cr = ARCH_R + rad * 0.12;
        // **ALTERNATING VOUSSOIRS** (Córdoba's own trick, gold for its red), and the gilt ones are the ones the weather took, so the alternation is broken in places.
        const gilded = @mod(i, 2) == 0 and rng.float() < 0.78;
        b.setMat(if (gilded) .gilt else .stone);
        b.addBox(
            v3(-ca * cr, ARCH_SPRING + sa * cr, rng.signed() * 0.016),
            v3(sa * half, ca * half, 0),
            v3(-ca * rad, sa * rad, 0),
            v3(0, 0, 0.60 * (if (key) @as(f32, 1.10) else 1.0)),
            if (gilded) goldTone(&rng) else ashlarTone(&rng),
        );
    }
    b.setMat(.stone);
    var s: i32 = 0;
    while (s < NV) : (s += 1) {
        if (s >= gone0 - 1 and s <= gone1 + 1) continue;
        const t = (@as(f32, @floatFromInt(s)) + 0.5) / @as(f32, NV);
        const a = mathx.radians(-HORSE_EXTRA + span * t);
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        const half = mathx.radians(span) * ARCH_R / @as(f32, NV) * 0.62;
        b.addBox(
            v3(-ca * (ARCH_R + 0.52), ARCH_SPRING + sa * (ARCH_R + 0.52), 0),
            v3(sa * half, ca * half, 0),
            v3(-ca * 0.19, sa * 0.19, 0),
            v3(0, 0, 0.56),
            ashlarTone(&rng),
        );
    }
    b.addBox(v3(-1.36, ARCH_SPRING + ARCH_R + 0.46, 0.02), v3(0.74, rng.signed() * 0.06, 0), v3(rng.signed() * 0.09, 0.44, 0), v3(0, 0, 0.62), ASHLAR);
    b.addCube(v3(-0.62, ARCH_SPRING + ARCH_R + 0.84, -0.03), v3(0.48, 0.36, 0.58), SCORCH);
    giltBandInto(&b, &rng, -1.36, ARCH_SPRING + ARCH_R + 0.50, 0, 0.76, 0.64, 0.10);

    for ([_]f32{ -ARCH_HALF, ARCH_HALF }) |x| {
        art.crackInto(&b, v3(x + 0.56, rng.range(0.7, 1.4), rng.signed() * 0.3), v3(rng.signed() * 0.2, 0.98, 0.05), v3(0, 0, 1), rng.range(0.9, 1.7), 0.020, 0.03);
        art.chipsInto(&b, &rng, x, 0, 1.6, 0.09, 0.24, 5);
    }
    b.setMat(.stone);
    b.addBox(v3(rng.range(-1.1, -0.4), 0.22, rng.range(-0.9, 0.9)), v3(0.36, rng.signed() * 0.12, 0.03), v3(rng.signed() * 0.14, 0.22, 0), v3(0, 0, 0.46), ASHLAR_DK);
    b.setMat(.gilt);
    b.addBox(v3(0.55, 0.17, rng.range(-1.0, 0.5)), v3(0.30, rng.signed() * 0.10, 0.02), v3(rng.signed() * 0.10, 0.16, 0), v3(0, 0, 0.40), GOLD);
    return b.toModel(shader);
}

// THE CORBEL FRAGMENT — the one place in the family where the honeycomb is at eye level. **IT NEEDED A WALL**: authored as a loose block the corbel photographed as shelves floating in the air.

pub const MUQ_W: f32 = 1.55;
pub const MUQ_WALL: f32 = 1.60;
pub const MUQ_TOP: f32 = 1.94;

pub fn muqarnasBlockMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x60_1D_A2);
    b.setMat(.stone);
    // Packed stone has a core (`courseInto`).
    art.courseInto(&b, &rng, -MUQ_W * 0.5, -0.30, MUQ_W * 0.5, -0.30, .{
        .thick = 0.34,
        .height = MUQ_WALL,
        .courses = 6,
        .blockW = 0.62,
        .crumbleTop = 0.55,
        .crumble = 0.05,
    });
    giltBandInto(&b, &rng, 0, 0.72, -0.30, MUQ_W * 0.44, 0.19, 0.13);
    // UNDER the wall's own top, not above it: a corbel carries something, so it cannot be the highest thing.
    // **AND ON BOTH FACES**, because a cornice runs both sides of a wall — authored on one, the honeycomb was invisible from every angle that showed the coursing.
    muqarnasInto(&b, &rng, v3(0, MUQ_WALL - 1.06, -0.13), v3(0, 0, 1), MUQ_W * 0.86, 0.94, 0.78);
    muqarnasInto(&b, &rng, v3(0, MUQ_WALL - 1.06, -0.47), v3(0, 0, -1), MUQ_W * 0.86, 0.94, 0.72);
    b.setMat(.stone);
    b.addBox(v3(0.10, MUQ_WALL + 0.16, -0.30), v3(MUQ_W * 0.34, rng.signed() * 0.05, 0.02), v3(rng.signed() * 0.04, 0.16, 0), v3(0, 0, 0.26), SCORCH);
    art.chipsInto(&b, &rng, 0, 0, 1.5, 0.07, 0.21, 8);
    art.crackInto(&b, v3(-0.44, 0.30, -0.13), v3(0.26, 0.96, 0), v3(0, 0, 1), 0.90, 0.018, 0.026);
    return b.toModel(shader);
}

// THE SPLIT DOME. A ribbed melon dome off a drum, cracked open across the crown. **A DOME IS A SHELL AND A SHELL HAS AN INSIDE** — the whole reason to break it open.

pub const DOME_R: f32 = 2.75;
pub const DOME_DRUM: f32 = 1.45;
pub const DOME_TOP: f32 = DOME_DRUM + DOME_R * 0.92;
const DOME_RIBS: i32 = 13;

pub fn giltDomeMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x60_1D_A3);

    b.setMat(.stone);
    const SIDES = OCTAGON;
    var s: i32 = 0;
    while (s < SIDES) : (s += 1) {
        const a0 = std.math.tau * @as(f32, @floatFromInt(s)) / @as(f32, SIDES);
        const a1 = std.math.tau * @as(f32, @floatFromInt(s + 1)) / @as(f32, SIDES);
        // The drum is WIDER than the shell that sits on it, so the springing course is visible all round: a shell that overhangs its own drum hides the building it is a roof for.
        const r0 = DOME_R * 1.06;
        art.courseInto(&b, &rng, mathx.cosf(a0) * r0, mathx.sinf(a0) * r0, mathx.cosf(a1) * r0, mathx.sinf(a1) * r0, .{
            .thick = 0.30,
            .height = DOME_DRUM,
            .courses = 5,
            .blockW = 0.66,
            .crumbleTop = 0.30,
            .crumble = 0.05,
        });
    }
    giltRingInto(&b, &rng, 0, DOME_DRUM - 0.16, 0, DOME_R * 1.09, 0.16, SIDES);

    // Ribs over the break stop short, so the hole has ragged edges rather than a cut line.
    const NSEG: i32 = 7;
    var k: i32 = 0;
    while (k < DOME_RIBS) : (k += 1) {
        const az = std.math.tau * (@as(f32, @floatFromInt(k)) + 0.5) / @as(f32, DOME_RIBS);
        const broken = k >= 4 and k <= 7;
        const upTo: i32 = if (broken) 3 + @as(i32, @intFromFloat(rng.range(0, 1.9))) else NSEG;
        // ONE RIB IN THREE, not one in two: at every other rib the shell photographed as a gold pinecone.
        const gilded = @mod(k, 3) == 0;
        var j: i32 = 0;
        while (j < upTo) : (j += 1) {
            const t0 = @as(f32, @floatFromInt(j)) / @as(f32, NSEG);
            const t1 = @as(f32, @floatFromInt(j + 1)) / @as(f32, NSEG);
            const e0 = std.math.pi * 0.5 * t0;
            const e1 = std.math.pi * 0.5 * t1;
            const rm = (mathx.cosf(e0) + mathx.cosf(e1)) * 0.5 * DOME_R;
            const ym = DOME_DRUM + (mathx.sinf(e0) + mathx.sinf(e1)) * 0.5 * DOME_R * 0.92;
            const along = (mathx.sinf(e1) - mathx.sinf(e0)) * DOME_R * 0.60;
            // NARROW: at 0.46 of the pitch the ribs met their neighbours and the shell read as scales.
            const wide = std.math.tau * rm / @as(f32, DOME_RIBS) * 0.30;
            b.setMat(if (gilded) .gilt else .stone);
            b.addBox(
                v3(mathx.cosf(az) * rm, ym, mathx.sinf(az) * rm),
                v3(-mathx.sinf(az) * wide, 0, mathx.cosf(az) * wide),
                v3(0, along, 0),
                v3(mathx.cosf(az) * 0.13, 0, mathx.sinf(az) * 0.13),
                if (gilded) goldTone(&rng) else ashlarTone(&rng),
            );
        }
        // The web between ribs — set BACK off them, which is what makes the ribs read as ribs.
        if (broken) continue;
        b.setMat(.stone);
        var w: i32 = 0;
        while (w < NSEG - 1) : (w += 1) {
            const t = (@as(f32, @floatFromInt(w)) + 0.5) / @as(f32, NSEG);
            const e = std.math.pi * 0.5 * t;
            const rm = mathx.cosf(e) * DOME_R * 0.99;
            const ym = DOME_DRUM + mathx.sinf(e) * DOME_R * 0.90;
            const az2 = az + std.math.tau / @as(f32, DOME_RIBS) * 0.5;
            b.addBox(
                v3(mathx.cosf(az2) * rm, ym, mathx.sinf(az2) * rm),
                v3(-mathx.sinf(az2) * (std.math.tau * rm / @as(f32, DOME_RIBS) * 0.66), 0, mathx.cosf(az2) * (std.math.tau * rm / @as(f32, DOME_RIBS) * 0.66)),
                v3(0, DOME_R * 0.90 / @as(f32, NSEG), 0),
                v3(mathx.cosf(az2) * 0.10, 0, mathx.sinf(az2) * 0.10),
                if (rng.float() < 0.24) SCORCH else ASHLAR_DK,
            );
        }
    }
    b.setMat(.gilt);
    b.addBlob(v3(0.62, DOME_DRUM + 0.24, -0.30), v3(0.34, 0.22, 0.30), 7, 9, GOLD_DK);
    b.setMat(.stone);
    art.chipsInto(&b, &rng, 0, 0, DOME_R * 1.15, 0.10, 0.26, 9);
    return b.toModel(shader);
}

// THE MINARET. An octagonal shaft snapped off two thirds up, with a corbelled balcony and a gilt band under it. LANDMARK scale.

pub const MIN_R: f32 = 0.86;
pub const MIN_H: f32 = 11.4;
pub const MIN_BALCONY: f32 = 7.30;
pub const MIN_TOP: f32 = MIN_H + 0.30;

pub fn minaretMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x60_1D_A4);
    const SIDES = OCTAGON;

    // A square base under an octagonal shaft, which is how every one of these is built.
    b.setMat(.stone);
    b.addBox(v3(0, 0.26, 0), v3(1.42, rng.signed() * 0.012, 0.02), v3(0, 0.26, 0), v3(0.02, 0, 1.42), ASHLAR_DK);
    _ = art.courseStack(&b, &rng, 0, 0.50, 0, 2.20, 2.14, 0.44, 4, 0.05);

    // LEANING — a tower this thin that stands plumb reads as a pipe. The lean is a whole-mesh shear applied per course by offsetting the ring centre.
    const LEAN: f32 = 0.16; // metres of drift at the break, over 9 m of shaft
    const CH: f32 = 0.52;
    const y0: f32 = 2.26;
    var y = y0;
    while (y < MIN_H - 0.9) : (y += CH) {
        const t = (y - y0) / (MIN_H - 0.9 - y0);
        const cx = LEAN * t * t;
        const rr = MIN_R * (1.0 - 0.10 * t);
        const ragged = t > 0.90;
        var s: i32 = 0;
        while (s < SIDES) : (s += 1) {
            if (ragged and rng.float() < 0.55) continue;
            const a0 = std.math.tau * @as(f32, @floatFromInt(s)) / @as(f32, SIDES);
            const a1 = std.math.tau * @as(f32, @floatFromInt(s + 1)) / @as(f32, SIDES);
            const mx = (mathx.cosf(a0) + mathx.cosf(a1)) * 0.5 * rr + cx;
            const mz = (mathx.sinf(a0) + mathx.sinf(a1)) * 0.5 * rr;
            const half = (mathx.sinf(a1 - a0) * 0.5) * rr * 1.06;
            const na = (a0 + a1) * 0.5;
            b.setMat(.stone);
            b.addBox(
                v3(mx, y + CH * 0.5, mz),
                v3(-mathx.sinf(na) * half, rng.signed() * 0.006, mathx.cosf(na) * half),
                v3(0, CH * 0.48 * rng.range(0.96, 1.04), 0),
                v3(mathx.cosf(na) * 0.20, 0, mathx.sinf(na) * 0.20),
                ashlarTone(&rng),
            );
        }
        if (@mod(@as(i32, @intFromFloat((y - y0) / CH)), 4) == 2 and rng.float() < 0.72) {
            b.setMat(.gilt);
            var g: i32 = 0;
            while (g < SIDES) : (g += 1) {
                if (rng.float() < 0.30) continue;
                const a = std.math.tau * (@as(f32, @floatFromInt(g)) + 0.5) / @as(f32, SIDES);
                b.addBox(
                    v3(mathx.cosf(a) * (rr + 0.03) + cx, y + CH * 0.5, mathx.sinf(a) * (rr + 0.03)),
                    v3(-mathx.sinf(a) * rr * 0.36, 0, mathx.cosf(a) * rr * 0.36),
                    v3(0, CH * 0.30, 0),
                    v3(mathx.cosf(a) * 0.055, 0, mathx.sinf(a) * 0.055),
                    goldTone(&rng),
                );
            }
        }
    }

    // THE BALCONY, on a muqarnas corbel — the one place the form steps out.
    const bx = LEAN * std.math.pow(f32, (MIN_BALCONY - y0) / (MIN_H - 0.9 - y0), 2.0);
    var q: i32 = 0;
    while (q < SIDES) : (q += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(q)) + 0.5) / @as(f32, SIDES);
        muqarnasInto(&b, &rng, v3(mathx.cosf(a) * (MIN_R * 0.78) + bx, MIN_BALCONY - 0.72, mathx.sinf(a) * (MIN_R * 0.78)), v3(mathx.cosf(a), 0, mathx.sinf(a)), 0.62, 0.72, 0.60);
    }
    b.setMat(.stone);
    b.addCylinder(v3(bx, MIN_BALCONY - 0.04, 0), v3(bx, MIN_BALCONY + 0.20, 0), MIN_R * 1.95, MIN_R * 1.88, SIDES, ASHLAR_LT);
    var p: i32 = 0;
    while (p < SIDES * 2) : (p += 1) {
        if (p >= 5 and p <= 9) continue;
        const a = std.math.tau * (@as(f32, @floatFromInt(p)) + 0.5) / @as(f32, SIDES * 2);
        const rr = MIN_R * 1.80;
        const gilded = @mod(p, 2) == 0;
        b.setMat(if (gilded) .gilt else .stone);
        b.addBox(
            v3(mathx.cosf(a) * rr + bx, MIN_BALCONY + 0.42, mathx.sinf(a) * rr),
            v3(-mathx.sinf(a) * 0.20, rng.signed() * 0.02, mathx.cosf(a) * 0.20),
            v3(rng.signed() * 0.03, 0.52, 0),
            v3(mathx.cosf(a) * 0.12, 0, mathx.sinf(a) * 0.12),
            if (gilded) goldTone(&rng) else ashlarTone(&rng),
        );
    }
    art.chipsInto(&b, &rng, 0, 0, 2.2, 0.10, 0.30, 11);
    art.crackInto(&b, v3(MIN_R + 0.02, 3.1, 0.2), v3(0.12, 0.98, 0.1), v3(0, 0, 1), 2.4, 0.022, 0.03);
    return b.toModel(shader);
}

// THE JALI SCREEN. A pierced lattice panel in a frame. **THE HOLES ARE THE OBJECT**: the lattice is drawn as the STONE between the voids, so the sun comes through it and lays the pattern on the ash.

pub const JALI_W: f32 = 3.20;
pub const JALI_H: f32 = 3.05;
pub const JALI_TOP: f32 = JALI_H + 0.20;
const JALI_LEAN: f32 = 11.0; // degrees off plumb — it is propped, not built

pub fn jaliScreenMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x60_1D_A5);
    const lean = mathx.radians(JALI_LEAN);
    const cl = mathx.cosf(lean);
    const sl = mathx.sinf(lean);
    // Every point on the panel is placed through this, so the lean is one number and not a per-shape guess.
    const at = struct {
        fn f(x: f32, y: f32, z: f32, c: f32, s: f32) rl.Vector3 {
            return v3(x, y * c, z + y * s);
        }
    }.f;

    b.setMat(.stone);
    b.addBox(at(0, 0.18, 0, cl, sl), v3(JALI_W * 0.5 + 0.22, 0, 0), v3(0, 0.18, 0), v3(0, 0, 0.30), ASHLAR_DK);
    for ([_]f32{ -1, 1 }) |sx| {
        b.addBox(
            at(sx * (JALI_W * 0.5 + 0.14), JALI_H * 0.5 + 0.2, 0, cl, sl),
            v3(0.15, 0, 0),
            v3(rng.signed() * 0.02, (JALI_H * 0.5 + 0.2) * cl, (JALI_H * 0.5 + 0.2) * sl),
            v3(0, 0, 0.26),
            ashlarTone(&rng),
        );
    }
    b.addBox(at(0, JALI_H + 0.10, 0, cl, sl), v3(JALI_W * 0.5 + 0.26, 0, 0), v3(0, 0.19, 0), v3(0, 0, 0.30), ASHLAR);
    // ONE PLATE along the panel — `giltBandInto` runs four plates round a square shaft, and on something 3.2 m wide and 0.3 m deep its cross-plates stuck out like gold planks.
    b.setMat(.gilt);
    var gx: i32 = 0;
    while (gx < 7) : (gx += 1) {
        if (rng.float() < 0.24) continue;
        const u = (@as(f32, @floatFromInt(gx)) + 0.5) / 7.0 - 0.5;
        b.addBox(
            at(u * JALI_W, JALI_H + 0.10, 0.16, cl, sl),
            v3(JALI_W / 7.0 * 0.44, 0, 0),
            v3(0, 0.075, 0),
            v3(0, -sl * 0.03, cl * 0.03),
            goldTone(&rng),
        );
    }

    // Bars on the two diagonals plus the two axes, which is what makes an eight-point star repeat.
    const COLS: i32 = 7;
    const ROWS: i32 = 7;
    const cw = JALI_W / @as(f32, COLS);
    const rh = (JALI_H - 0.36) / @as(f32, ROWS);
    var r: i32 = 0;
    while (r < ROWS) : (r += 1) {
        var c: i32 = 0;
        while (c < COLS) : (c += 1) {
            if (r >= ROWS - 2 and c <= 1) continue; // the corner that fell out
            if (rng.float() < 0.06) continue;
            const cx = (@as(f32, @floatFromInt(c)) + 0.5 - @as(f32, COLS) * 0.5) * cw;
            const cy = 0.30 + (@as(f32, @floatFromInt(r)) + 0.5) * rh;
            const gilded = @mod(r + c, 3) == 0 and rng.float() < 0.62;
            b.setMat(if (gilded) .gilt else .stone);
            const col = if (gilded) goldTone(&rng) else ashlarTone(&rng);
            // The star's own two squares at cell scale; the voids between them are the piercing.
            for ([_]f32{ 0, 45.0 }) |deg| {
                const a = mathx.radians(deg + rng.signed() * 2.0);
                const ca = mathx.cosf(a);
                const sa = mathx.sinf(a);
                // INTERLOCKING: at 0.46 of the pitch the cells stood apart and the panel read as a rack of biscuits. Past 0.5 they touch.
            const arm = @min(cw, rh) * 0.68;
                b.addBox(
                    at(cx, cy, 0, cl, sl),
                    v3(ca * arm, sa * arm * cl, sa * arm * sl),
                    v3(-sa * 0.055, ca * 0.055 * cl, ca * 0.055 * sl),
                    v3(0, -sl * 0.10, cl * 0.10),
                    col,
                );
            }
        }
    }
    b.setMat(.stone);
    art.chipsInto(&b, &rng, 0, 0.3, 1.7, 0.07, 0.19, 7);
    b.addBox(v3(rng.range(-1.2, -0.5), 0.11, 0.9), v3(0.44, rng.signed() * 0.05, 0.03), v3(0, 0.09, 0), v3(0.02, 0, 0.40), ASHLAR_DK);
    return b.toModel(shader);
}

// THE COLUMN. Slender, standing, muqarnas capital, gilt necking — the mid-layer piece sown in numbers so the region reads as a hall that lost its roof.

pub const COL_H: f32 = 4.35;
pub const COL_R: f32 = 0.40;
pub const COL_TOP: f32 = COL_H + 0.55;

pub fn giltColumnMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x60_1D_A6);
    b.setMat(.stone);
    // Two square plinths, the upper turned a few degrees off the lower.
    b.addBox(v3(0, 0.14, 0), v3(0.72, 0, 0.03), v3(0, 0.14, 0), v3(0.03, 0, 0.72), ASHLAR_DK);
    b.addBox(v3(0, 0.38, 0), v3(0.58, 0, 0.09), v3(0, 0.11, 0), v3(0.09, 0, 0.56), ASHLAR);
    // Sixteen flutes: `addCylinder` alone leaves a pipe (AGENTS.md).
    const FL: i32 = 16;
    var f: i32 = 0;
    while (f < FL) : (f += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(f)) + 0.5) / @as(f32, FL);
        const rr = COL_R * rng.range(0.99, 1.02);
        b.addCapsule(
            v3(mathx.cosf(a) * rr, 0.48, mathx.sinf(a) * rr),
            v3(mathx.cosf(a) * rr * 0.86 + rng.signed() * 0.01, COL_H - 0.55, mathx.sinf(a) * rr * 0.86),
            0.055,
            0.048,
            5,
            ashlarTone(&rng),
        );
    }
    b.addCylinder(v3(0, 0.46, 0), v3(0, COL_H - 0.52, 0), COL_R * 0.90, COL_R * 0.78, 12, ASHLAR_DK);
    giltRingInto(&b, &rng, 0, 0.62, 0, COL_R * 1.06, 0.11, 12);
    giltRingInto(&b, &rng, 0, COL_H - 0.66, 0, COL_R * 0.98, 0.14, 12);
    // A muqarnas block on each of four faces, so it grows out to a square abacus.
    for ([_][2]f32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |s| {
        muqarnasInto(
            &b,
            &rng,
            v3(s[0] * COL_R * 0.42, COL_H - 0.60, s[1] * COL_R * 0.42),
            v3(s[0], 0, s[1]),
            0.72,
            0.62,
            0.68,
        );
    }
    b.setMat(.stone);
    b.addBox(v3(rng.signed() * 0.02, COL_H + 0.10, rng.signed() * 0.02), v3(0.62, rng.signed() * 0.02, 0.04), v3(0, 0.13, 0), v3(0.04, 0, 0.60), ASHLAR_LT);
    b.addBox(v3(0.10, COL_H + 0.36, 0.06), v3(0.30, rng.signed() * 0.06, 0), v3(rng.signed() * 0.05, 0.20, 0), v3(0, 0, 0.34), SCORCH);
    art.chipsInto(&b, &rng, 0, 0, 0.9, 0.06, 0.15, 5);
    return b.toModel(shader);
}

// THE STAR BASIN. An eight-point fountain basin, bone dry, gilt-lined, filled to the brim with ash. Knee-high ground furniture.

pub const BASIN_R: f32 = 1.70;
pub const BASIN_TOP: f32 = 0.98;

pub fn giltBasinMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x60_1D_A7);
    b.setMat(.stone);
    // The plan is the khatim, twice: a wide low apron and the basin standing on it.
    starInto(&b, &rng, v3(0, 0.09, 0), BASIN_R, 0.18, ASHLAR_DK);
    starInto(&b, &rng, v3(0, 0.26, 0), BASIN_R * 0.86, 0.18, ASHLAR);
    // **AND IT IS A BOWL, WHICH MEANS IT HAS A WALL.** It shipped once as two flat slabs with gold plates lying on them, which photographed as ingots on a doorstep.
    var w: i32 = 0;
    while (w < 16) : (w += 1) {
        const a = std.math.tau * (@as(f32, @floatFromInt(w)) + 0.5) / 16.0;
        const rr = BASIN_R * 0.74;
        const gone = rng.float() < 0.12;
        if (gone) continue;
        b.setMat(.stone);
        b.addBox(
            v3(mathx.cosf(a) * rr, 0.46, mathx.sinf(a) * rr),
            v3(-mathx.sinf(a) * (std.math.tau * rr / 16.0 * 0.60), rng.signed() * 0.008, mathx.cosf(a) * (std.math.tau * rr / 16.0 * 0.60)),
            v3(0, 0.22, 0),
            v3(mathx.cosf(a) * 0.13, 0, mathx.sinf(a) * 0.13),
            ashlarTone(&rng),
        );
        // …and the gilt coping ON that wall, so the gold sits where a hand would rest.
        if (rng.float() < 0.32) continue;
        b.setMat(.gilt);
        b.addBox(
            v3(mathx.cosf(a) * rr, 0.70 + rng.signed() * 0.012, mathx.sinf(a) * rr),
            v3(-mathx.sinf(a) * (std.math.tau * rr / 16.0 * 0.62), rng.signed() * 0.014, mathx.cosf(a) * (std.math.tau * rr / 16.0 * 0.62)),
            v3(0, 0.035, 0),
            v3(mathx.cosf(a) * 0.16, 0, mathx.sinf(a) * 0.16),
            goldTone(&rng),
        );
    }
    b.setMat(.plain);
    b.addBlob(v3(0.12, 0.50, -0.06), v3(BASIN_R * 0.60, 0.16, BASIN_R * 0.56), 7, 11, art.DRIFT);
    b.addBlob(v3(-0.28, 0.56, 0.20), v3(BASIN_R * 0.28, 0.10, BASIN_R * 0.26), 6, 9, art.DRIFT_LT);
    b.setMat(.gilt);
    b.addCylinder(v3(0, 0.40, 0), v3(rng.signed() * 0.04, 0.86, rng.signed() * 0.04), 0.13, 0.09, 8, GOLD_DK);
    b.addDome(v3(rng.signed() * 0.04, 0.86, rng.signed() * 0.04), v3(0, 1, 0), 0.12, 9, GOLD);
    b.setMat(.stone);
    art.chipsInto(&b, &rng, 0, 0, BASIN_R * 1.1, 0.05, 0.14, 7);
    return b.toModel(shader);
}

// THE FALLEN FINIAL. Ground clutter: the crescent off the top of something, lying in its own rubble. **A REGION NEEDS THREE LAYERS** (AGENTS.md) and this is the ground-hugger.

pub const FINIAL_TOP: f32 = 0.95;

pub fn giltFinialMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x60_1D_A8);
    // The rubble it landed in, first — the finial sits ON this, not beside it.
    b.setMat(.stone);
    b.addBlob(v3(0, 0.13, 0), v3(0.82, 0.13, 0.74), 6, 10, ASHLAR_DK);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const rr = rng.range(0.18, 0.78);
        b.addBox(
            v3(mathx.cosf(a) * rr, rng.range(0.10, 0.24), mathx.sinf(a) * rr),
            v3(rng.range(0.10, 0.24), rng.signed() * 0.05, 0.02),
            v3(rng.signed() * 0.04, rng.range(0.06, 0.13), 0),
            v3(0.02, 0, rng.range(0.09, 0.22)),
            ashlarTone(&rng),
        );
    }
    b.setMat(.gilt);
    b.addCapsule(v3(-0.62, 0.20, 0.14), v3(0.18, 0.30, -0.08), 0.055, 0.048, 7, GOLD_DK);
    b.addCapsule(v3(0.18, 0.30, -0.08), v3(0.44, 0.42, -0.02), 0.048, 0.042, 7, GOLD);
    // Two arcs of small blocks, the inner set back, so it is a crescent and not a doughnut. **IT HAS TO BE A
    // RING WITH A BITE OUT OF IT**, which means a real circle in a real plane: driven off one angle into both x and z it came out a flattened ellipse seen edge-on.
    const CR: f32 = 0.34;
    const NC: i32 = 11;
    const hub = v3(0.46, 0.48, -0.02);
    // The plane the crescent lies in — tipped off vertical, because it fell.
    const cu = mathx.normV(v3(0.86, 0.18, 0.48));
    const cw = mathx.normV(v3(-0.24, 0.94, 0.10));
    var k: i32 = 0;
    while (k < NC) : (k += 1) {
        const t = (@as(f32, @floatFromInt(k)) + 0.5) / @as(f32, NC);
        // The OPENING is the gap between the horns: 246 degrees of ring and 114 of nothing.
        const a = mathx.radians(-123.0 + 246.0 * t);
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        // Tapers to the horns, because a crescent is thick at its back and thin at its points.
        const thick = 0.075 * (0.45 + 0.55 * mathx.cosf(a * 0.5));
        const px = hub.x + cu.x * ca * CR + cw.x * sa * CR;
        const py = hub.y + cu.y * ca * CR + cw.y * sa * CR;
        const pz = hub.z + cu.z * ca * CR + cw.z * sa * CR;
        b.addBox(
            v3(px, py, pz),
            v3((-cu.x * sa + cw.x * ca) * CR * (std.math.pi * 1.37 / @as(f32, NC)), (-cu.y * sa + cw.y * ca) * CR * (std.math.pi * 1.37 / @as(f32, NC)), (-cu.z * sa + cw.z * ca) * CR * (std.math.pi * 1.37 / @as(f32, NC))),
            v3((cu.x * ca + cw.x * sa) * thick, (cu.y * ca + cw.y * sa) * thick, (cu.z * ca + cw.z * sa) * thick),
            v3(0.055, 0.02, -0.10),
            goldTone(&rng),
        );
    }
    b.setMat(.stone);
    art.chipsInto(&b, &rng, 0, 0, 1.0, 0.04, 0.11, 6);
    return b.toModel(shader);
}

test "the family's forms are the ARABIC ones, and its three layers are three heights" {
    // The mesh builders upload through GL, so what is pinned here is the SPEC they are laid out from.
    try std.testing.expect(HORSE_EXTRA > 20.0); // a horseshoe, not a Roman arch
    // MEASURED: the top tier hangs `MUQ_STEP * (MUQ_TIERS - 1)` of the rise past the wall, which is 0.45 of it.
    try std.testing.expect(MUQ_TIERS >= 3);
    try std.testing.expect(MUQ_STEP > 0.08 and MUQ_STEP * @as(f32, @floatFromInt(MUQ_TIERS - 1)) < 0.6);
    try std.testing.expect(JALI_LEAN > 5.0); // propped, not built
    try std.testing.expect(ARCH_TOP > DOME_TOP and MIN_TOP > ARCH_TOP); // three layers, and the tower is the landmark
    // …and the ground furniture stays under the knee-and-a-half a player steps over.
    try std.testing.expect(FINIAL_TOP < 1.0 and BASIN_TOP < 1.1);
}

test "the palette reads PALE against ash and the gold is authored DIM for its own shine" {
    // Screen goes through `gfx.screenOf`, which is the shader's own key and gamma and is pinned to them. The
    // ashlar has to come up brighter than `propart.DRIFT`, which is what the region is made of. RED channel:
    // this family is warm and its red is the one that carries.
    const lit = struct {
        fn f(c: rl.Color) f32 {
            return gfx.screenOf(@floatFromInt(c.r));
        }
    }.f;
    const ashlar = lit(ASHLAR);
    const drift = lit(art.DRIFT);
    std.debug.print("\n  gilt family: ashlar {d:.0} on screen, ash drift {d:.0}, gold base {d:.0} (its shine is the shader's)\n", .{ ashlar, drift, lit(GOLD) });
    try std.testing.expect(ashlar > drift * 1.10);
    // …and the gold's albedo stays under the stone's screen value: `Mat.gilt` adds a 2.4 hotspot and a warm rim, and a bright base under that is a flat lemon.
    try std.testing.expect(lit(GOLD) < ashlar);
    // Warm by a MARGIN — a grey-yellow gold is a brass doorknob.
    try std.testing.expect(@as(f32, @floatFromInt(GOLD.r)) > @as(f32, @floatFromInt(GOLD.b)) * 3.0 and GOLD.g > GOLD.b);
}
