const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");
const art = @import("propart.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;
const CAP_FLESH = art.CAP_FLESH;
const CAP_FLESH_DK = art.CAP_FLESH_DK;
const CAP_RIM = art.CAP_RIM;
const GILL = art.GILL;
const STIPE = art.STIPE;
const STIPE_DK = art.STIPE_DK;
const CAP_GLOW = art.CAP_GLOW;
const SPORE_GLOW = art.SPORE_GLOW;
const PUNK = art.PUNK;
const PUNK_DK = art.PUNK_DK;
const BARK_OLD = art.BARK_OLD;


// ── THE MYCELIAN ────────────────────────────────────────────────────────────────────────────────────────
//
// A wood with no wood in it. The three layers a region owes are all fungal here — a canopy of caps you walk
// under, brackets and clusters for understorey, pods on the floor — which is what stops it reading as a
// forest that had its trees swapped out.
//
// **THE GILLS ARE THE WHOLE THING.** A cap without them is an umbrella, and they are the one surface in the
// world that is permanently in its own shade — so `GILL` is authored PALE where every other albedo here is
// authored near-black. It never takes the sun, so the hot key never gets at it.

/// How far under the cap the gills are laid, as a share of the cap's own drop. Deep enough to be in shadow
/// from any angle you can stand at, shallow enough that the rim still reads as an edge.
const GILL_IN: f32 = 0.62;

/// **AT THE CAP'S OWN CENTRE, NOT AT THE ORIGIN.** Every cap here LEANS, so its crown sits off the axis its
/// stalk came out of — and the gills were being laid at 0,0 regardless. On a 6-degree lean over 6.4 m that is
/// half a metre of offset, which is why they came out of one side of the brim as a saw blade. Pulling the
/// radius in hid it; this is the reason.
fn gillsInto(b: *Builder, cx: f32, cz: f32, r: f32, y: f32, drop: f32, n: i32, col: rl.Color) void {
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(@max(n, 1)));
        const c = mathx.cosf(a);
        const s = mathx.sinf(a);
        // INSIDE THE RIM. At 0.94 plus the blob's own padding these stood proud of the cap's edge and read
        // as a saw blade; the rim shell is at 1.01, so the gills have to stop well short of it.
        const inner = r * 0.18;
        const outer = r * 0.88;
        const mid = (inner + outer) * 0.5;
        // A blade, radial: thin across, deep along, and it hangs BELOW the cap's own underside.
        b.addBlob(
            v3(cx + c * mid, y - drop * GILL_IN, cz + s * mid),
            v3(@abs(c) * (outer - inner) * 0.5 + r * 0.012, drop * 0.11, @abs(s) * (outer - inner) * 0.5 + r * 0.012),
            2,
            5,
            col,
        );
    }
}

pub const CapSpec = struct {
    h: f32,
    capR: f32,
    /// How far the cap's rim hangs below its crown — a flat cap is a plate.
    drop: f32,
    stipeR: f32,
    /// Degrees off plumb. Nothing that grew is plumb.
    lean: f32 = 0,
    gills: i32 = 16,
    warts: i32 = 0,
    glow: bool = false,
    /// **THE VARIATION LIVES HERE.** One canopy mesh placed a dozen times reads as a periodic pattern and
    /// yaw and scale do not hide it (the `bigtree` law) — so the three great caps differ in proportion AND
    /// in tone, and neither is varied along a single cap.
    flesh: rl.Color = CAP_FLESH,
    fleshDk: rl.Color = CAP_FLESH_DK,
    rim: rl.Color = CAP_RIM,
};

fn capInto(b: *Builder, rng: *mathx.Rng, sp: CapSpec, cx: f32, cz: f32, yaw: f32) void {
    const lean = mathx.radians(sp.lean);
    const dir = v3(mathx.sinf(lean) * mathx.cosf(yaw), mathx.cosf(lean), mathx.sinf(lean) * mathx.sinf(yaw));
    const foot = v3(cx, 0, cz);
    const head = mathx.addV(foot, mathx.scaleV(dir, sp.h));

    b.setMat(.plant);
    // The BULB it comes out of the ground on, then a stipe that narrows and flares again under the cap.
    b.addBlob(v3(cx, sp.stipeR * 0.85, cz), v3(sp.stipeR * 1.75, sp.stipeR * 1.05, sp.stipeR * 1.65), 3, 8, STIPE_DK);
    const waist = mathx.addV(foot, mathx.scaleV(dir, sp.h * 0.55));
    b.addCapsule(foot, waist, sp.stipeR * 1.15, sp.stipeR * 0.82, 8, STIPE);
    b.addCapsule(waist, head, sp.stipeR * 0.82, sp.stipeR * 1.05, 8, STIPE_DK);

    // The ring — what is left of the veil that covered the gills before it opened.
    const ring = mathx.addV(foot, mathx.scaleV(dir, sp.h * 0.74));
    b.addBlob(ring, v3(sp.stipeR * 1.7, sp.stipeR * 0.20, sp.stipeR * 1.7), 2, 8, GILL);

    gillsInto(b, head.x, head.z, sp.capR, head.y, sp.drop, sp.gills, if (sp.glow) CAP_GLOW else GILL);

    // The cap itself, as two shells: the crown, and a rim that turns DOWN under it.
    b.setMat(.plant);
    b.addBlob(v3(head.x, head.y, head.z), v3(sp.capR, sp.drop * 1.35, sp.capR), 5, 12, sp.fleshDk);
    b.addBlob(v3(head.x, head.y + sp.drop * 0.30, head.z), v3(sp.capR * 0.74, sp.drop * 1.15, sp.capR * 0.74), 4, 11, sp.flesh);
    b.addBlob(v3(head.x, head.y - sp.drop * 0.28, head.z), v3(sp.capR * 1.01, sp.drop * 0.30, sp.capR * 1.01), 2, 12, sp.rim);

    // WARTS ARE RELIEF, so they are a few per cent of the cap and sunk most of the way into it.
    var i: i32 = 0;
    while (i < sp.warts) : (i += 1) {
        const a = rng.angle();
        const d = @sqrt(rng.float()) * sp.capR * 0.82;
        const r = sp.capR * rng.range(0.026, 0.055);
        const up = sp.drop * 1.15 * @sqrt(mathx.maxF(1.0 - (d / sp.capR) * (d / sp.capR), 0));
        b.addBlob(
            v3(head.x + mathx.cosf(a) * d, head.y + up * 0.86, head.z + mathx.sinf(a) * d),
            v3(r, r * 0.55, r),
            2,
            5,
            sp.rim,
        );
    }
}

pub const GIANT_H: f32 = 6.4;
pub const GIANT_R: f32 = 3.3;
pub const GIANT_DROP: f32 = 0.95;
pub const GIANT_STIPE: f32 = 0.52;

/// **THREE CANOPIES, NOT ONE AT THREE SCALES** — `bigtree`/`bigtree2`/`bigtree3`'s reason exactly. A parasol,
/// a broad one and a squat table, and they separate on HUE as well as proportion because a wood of one
/// silhouette at three sizes still reads as a pattern from any distance you can see the crowns at.
pub const GIANT_BROAD = CapSpec{ .h = GIANT_H, .capR = GIANT_R, .drop = GIANT_DROP, .stipeR = GIANT_STIPE, .lean = 6.0, .gills = 40, .warts = 14 };
pub const GIANT_TALL = CapSpec{
    .h = 8.3,
    .capR = 2.35,
    .drop = 1.40,
    .stipeR = 0.44,
    .lean = 11.0,
    .gills = 34,
    .warts = 6,
    .flesh = rgba(38, 34, 44, 255),
    .fleshDk = rgba(25, 22, 30, 255),
    .rim = rgba(52, 46, 58, 255),
};
pub const GIANT_TABLE = CapSpec{
    .h = 4.9,
    .capR = 3.95,
    .drop = 0.58,
    .stipeR = 0.66,
    .lean = 3.0,
    .gills = 46,
    .warts = 26,
    .flesh = rgba(50, 41, 34, 255),
    .fleshDk = rgba(33, 27, 22, 255),
    .rim = rgba(64, 53, 43, 255),
};

// **THE YOUNG ONE'S PLACE IS THE MESH'S, AND SO IS EVERY NUMBER THE TABLE CARRIES.** All four were typed
// into `props.INFO` by hand next to a mesh that computes them, and they drifted the moment a spec moved: the
// broad cap's second collider sat 0.10 m off the stipe it is meant to be, and the parasol under-declared its
// own `top` by a metre — which culls a 10 m mushroom out of the shadow pass while you are standing under it.
pub const YOUNG_OUT: f32 = 0.68;
pub const YOUNG_SIDE: f32 = -0.40;
pub const YOUNG_H: f32 = 0.32;
pub const YOUNG_STIPE: f32 = 0.38;

/// The crown of the taller of the two shells, which is the highest thing on the prop.
pub fn capTop(sp: CapSpec) f32 {
    return sp.h + sp.drop * 1.45;
}

/// …and the sphere that holds it: the crown, or the rim swung out at cap radius, whichever reaches further.
pub fn capBound(sp: CapSpec) f32 {
    const rim = @sqrt(sp.capR * sp.capR + (sp.h - sp.drop * 0.28) * (sp.h - sp.drop * 0.28));
    return mathx.maxF(capTop(sp), rim) + 0.25;
}

/// Both stipes. The cap is a ROOF: neither collider reaches it, so you walk under.
pub fn capParts(sp: CapSpec) [2]art.Part {
    const yx = sp.capR * YOUNG_OUT;
    const yz = sp.capR * YOUNG_SIDE;
    return .{
        .{ .r = sp.stipeR * 1.19, .h = sp.h * 0.78 },
        .{ .ax = yx, .az = yz, .bx = yx, .bz = yz, .r = sp.stipeR * YOUNG_STIPE * 1.30, .h = sp.h * YOUNG_H * 0.88 },
    };
}

/// Bole then crown, `bigtree`'s reason: one cylinder cannot be narrow at the foot and a cap's width at the brim.
pub fn capOccl(sp: CapSpec) [2]art.Blocker {
    return .{
        .{ .r = sp.stipeR * 1.70, .y1 = sp.h * 0.82 },
        .{ .r = sp.capR * 1.03, .y0 = sp.h * 0.79, .y1 = capTop(sp) },
    };
}

fn giantModel(shader: rl.Shader, seed: u64, sp: CapSpec, yaw: f32) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(seed);
    capInto(&b, &rng, sp, 0, 0, yaw);
    // A young one beside it, a third the height — the same organism twice, which is how fungus grows.
    var young = sp;
    young.h = sp.h * YOUNG_H;
    young.capR = sp.capR * 0.32;
    young.drop = sp.drop * 0.36;
    young.stipeR = sp.stipeR * YOUNG_STIPE;
    young.lean = sp.lean * 2.1;
    young.gills = 12;
    young.warts = @divTrunc(sp.warts, 3);
    capInto(&b, &rng, young, sp.capR * YOUNG_OUT, sp.capR * YOUNG_SIDE, yaw + 1.7);
    b.setMat(.plant);
    return b.toModel(shader);
}

/// **THE CANOPY.** You walk under these, so the collider is the stipe and nothing else.
pub fn capGiantMesh(shader: rl.Shader) rl.Model {
    return giantModel(shader, 0xF0A1, GIANT_BROAD, 0.7);
}
pub fn capGiant2Mesh(shader: rl.Shader) rl.Model {
    return giantModel(shader, 0xF0A6, GIANT_TALL, 2.4);
}
pub fn capGiant3Mesh(shader: rl.Shader) rl.Model {
    return giantModel(shader, 0xF0A7, GIANT_TABLE, 4.1);
}

/// The understorey: four at knee-to-shoulder height off one mat, no two alike.
pub fn capClusterMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF0A2);
    const N = 4;
    var i: i32 = 0;
    while (i < N) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.10, 0.72);
        const h = rng.range(0.95, 2.35);
        capInto(&b, &rng, .{
            .h = h,
            .capR = h * rng.range(0.30, 0.46),
            .drop = h * 0.17,
            .stipeR = h * 0.085,
            .lean = rng.range(5.0, 21.0),
            .gills = 10 + rng.intn(6),
            .warts = rng.intn(5),
        }, mathx.cosf(a) * d, mathx.sinf(a) * d, rng.angle());
    }
    b.setMat(.plant);
    return b.toModel(shader);
}

pub const BRACKET_H: f32 = 2.4;

/// Shelves stepping up a rotted stub — the one fungus here that needs something dead to stand on, so it
/// brings its own.
pub fn bracketMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF0A3);
    b.setMat(.bark);
    const lean = mathx.radians(7.0);
    const dir = v3(mathx.sinf(lean), mathx.cosf(lean), 0);
    b.addCapsule(v3(0, 0, 0), mathx.scaleV(dir, BRACKET_H), 0.42, 0.30, 8, BARK_OLD);
    b.addDome(mathx.scaleV(dir, BRACKET_H), dir, 0.30, 7, PUNK_DK);
    b.addBlob(v3(0, 0.14, 0), v3(0.66, 0.18, 0.62), 3, 8, PUNK_DK);

    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const t = 0.16 + 0.72 * @as(f32, @floatFromInt(i)) / 6.0;
        const a = rng.angle();
        const y = BRACKET_H * t;
        const stub = 0.42 - 0.12 * t;
        const out = rng.range(0.34, 0.62) * (1.0 - 0.35 * t);
        const c = mathx.cosf(a);
        const s = mathx.sinf(a);
        const cx = c * (stub + out * 0.55);
        const cz = s * (stub + out * 0.55);
        // A HALF-DISC ON EDGE, not a plate: it is thick where it meets the wood and thin at its lip.
        b.addBlob(v3(cx, y, cz), v3(out * (0.55 + 0.45 * @abs(c)), rng.range(0.05, 0.10), out * (0.55 + 0.45 * @abs(s))), 2, 8, art.weathered(CAP_FLESH_DK, CAP_FLESH, t));
        b.addBlob(v3(cx, y - 0.035, cz), v3(out * 0.86 * (0.55 + 0.45 * @abs(c)), 0.028, out * 0.86 * (0.55 + 0.45 * @abs(s))), 2, 7, GILL);
    }
    return b.toModel(shader);
}

pub const GLOW_H: f32 = 2.5;
pub const GLOW_LIGHT_Y: f32 = GLOW_H - 0.30;

/// **THE ONE THING IN THE REGION THAT IS ACTUALLY A LIGHT.** Everything else here glows through its vertex
/// alpha, which costs nothing and lights nothing; this carries a real `LightSpec` so the ground under it
/// takes a pool. Cold, and barely flickering — a fungus does not gutter.
pub fn glowCapMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF0A4);
    capInto(&b, &rng, .{
        .h = GLOW_H,
        .capR = 1.15,
        .drop = 0.40,
        .stipeR = 0.17,
        .lean = 9.0,
        .gills = 18,
        .warts = 6,
        .glow = true,
    }, 0, 0, 1.9);
    // Spores coming off the gills, hanging in the still air under the cap.
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 9) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.2, 1.0);
        const r = rng.range(0.020, 0.045);
        b.addBlob(v3(mathx.cosf(a) * d, GLOW_H - rng.range(0.35, 1.30), mathx.sinf(a) * d), v3(r, r, r), 2, 5, SPORE_GLOW);
    }
    return b.toModel(shader);
}

pub const POD_H: f32 = 1.15;

/// Ground cover, and the only one of these that SWAYS — `setAnimY` is what puts a vertex in the wind, and
/// the stalk is thin enough to earn it where a cap the size of a roof is not.
pub fn sporePodMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF0A5);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 6) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.0, 0.30);
        const h = POD_H * rng.range(0.55, 1.0);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const tipx = x + rng.signed() * h * 0.16;
        const tipz = z + rng.signed() * h * 0.16;
        b.setAnimY(h * 0.5);
        b.addCapsule(v3(x, 0, z), v3(tipx, h * 0.86, tipz), 0.030, 0.022, 5, STIPE);
        b.setAnimY(h);
        const pr = rng.range(0.055, 0.105);
        b.addBlob(v3(tipx, h * 0.86 + pr * 0.7, tipz), v3(pr, pr * rng.range(1.3, 1.9), pr), 3, 6, if (rng.float() < 0.45) SPORE_GLOW else CAP_FLESH);
    }
    b.setAnimY(0);
    return b.toModel(shader);
}

test "a cap hangs its gills in its own shade, and they are the one pale albedo here" {
    // The gills sit BELOW the cap's underside by most of its drop, which is what keeps them unlit from any
    // angle a body can stand at — and why they may be authored light when everything outdoors is authored dark.
    try std.testing.expect(GILL_IN > 0.5 and GILL_IN < 1.0);
    try std.testing.expect(@as(f32, @floatFromInt(GILL.r)) > @as(f32, @floatFromInt(CAP_FLESH.r)) * 1.5);
    try std.testing.expect(CAP_FLESH_DK.r < CAP_FLESH.r);
}

test "THE THREE LAYERS ARE ALL FUNGAL — canopy, understorey and floor, and they do not overlap" {
    // A region needs a ground-hugger, an understorey and a canopy or it reads sparse however many props are
    // in it. This kingdom has no wood at all, so all three have to come out of this file.
    try std.testing.expect(POD_H < BRACKET_H);
    try std.testing.expect(BRACKET_H < GIANT_H * 0.5);
    try std.testing.expect(GLOW_H < GIANT_H * 0.5);
    // …and you walk UNDER the canopy: the cap's underside clears a 1.8 m man with room over him.
    try std.testing.expect(GIANT_H - GIANT_DROP * 1.35 > 1.8 + 0.4);
    // …and so does every other canopy kind, or one of the three is a ceiling you walk into.
    inline for (.{ GIANT_BROAD, GIANT_TALL, GIANT_TABLE }) |sp| {
        try std.testing.expect(sp.h - sp.drop * 1.35 > 2.2);
    }
    // THREE SILHOUETTES: no two share a crown height or a cap radius inside a metre.
    try std.testing.expect(@abs(GIANT_BROAD.h - GIANT_TALL.h) > 1.0);
    try std.testing.expect(@abs(GIANT_BROAD.h - GIANT_TABLE.h) > 1.0);
    try std.testing.expect(@abs(GIANT_TALL.capR - GIANT_TABLE.capR) > 1.0);
}

test "the glow's light sits under its own cap rather than on top of it" {
    try std.testing.expect(GLOW_LIGHT_Y < GLOW_H);
    try std.testing.expect(GLOW_LIGHT_Y > GLOW_H * 0.5);
    // Emissive alpha, not opacity: both fungal glows read as self-lit to the scene shader.
    try std.testing.expect(CAP_GLOW.a < 255 and SPORE_GLOW.a < 255);
}

// ── BIGGER, WEIRDER, AND MORE OF IT LIT ─────────────────────────────────────────────────────────────────
//
// The three great caps are a wood. These are the things that make it a KINGDOM: one cap at landmark scale,
// two structures nothing grew on purpose, and three more sources of light so the floor is never black.

/// **THE COLOSSAL CAP.** Seventeen metres to the crown — `tower` scale, and the only fungus you navigate by.
/// It is the same `CapSpec` as the other three, so its table numbers come off the same solve.
pub const GIANT_COLOSSAL = CapSpec{
    .h = 14.5,
    .capR = 7.2,
    .drop = 1.90,
    .stipeR = 1.15,
    .lean = 4.0,
    .gills = 64,
    .warts = 34,
    .flesh = rgba(46, 36, 40, 255),
    .fleshDk = rgba(27, 21, 25, 255),
    .rim = rgba(60, 47, 50, 255),
};

pub fn capColossalMesh(shader: rl.Shader) rl.Model {
    return giantModel(shader, 0xF0A8, GIANT_COLOSSAL, 1.3);
}

pub const TOWER_H: f32 = 9.4;
pub const TOWER_R: f32 = 1.9;

/// **A COLUMN OF FUSED CAPS.** Six grown through one another, each smaller than the last, so it reads as a
/// thing that kept going rather than a thing that was built. Weathered foot to tip on `art.weathered` and
/// never banded per tier — that is the barber's pole the whole prop set was just cleaned of.
pub fn capTowerMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF0A9);
    b.setMat(.plant);
    const N = 6;
    const lean = mathx.radians(5.5);
    var i: i32 = 0;
    while (i < N) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / (N - 1);
        const y = TOWER_H * (0.10 + 0.90 * t);
        const off = mathx.sinf(lean) * y;
        const r = TOWER_R * (1.0 - 0.62 * t) * rng.range(0.92, 1.08);
        const drop = r * 0.34;
        // The shelf, and the gills under it — a tier with no gills is a plate on a pole.
        gillsInto(&b, off, 0, r, y, drop, 12 + @as(i32, @intFromFloat(r * 6.0)), GILL);
        b.setMat(.plant);
        b.addBlob(v3(off, y, 0), v3(r, drop * 1.25, r * rng.range(0.88, 1.12)), 4, 11, art.weathered(CAP_FLESH_DK, CAP_RIM, t));
        b.addBlob(v3(off, y - drop * 0.30, 0), v3(r * 1.01, drop * 0.26, r * 1.01), 2, 11, art.weathered(CAP_FLESH, CAP_RIM, t));
    }
    const top = v3(mathx.sinf(lean) * TOWER_H, TOWER_H, 0);
    b.addCapsule(v3(0, 0, 0), top, TOWER_R * 0.42, TOWER_R * 0.20, 9, STIPE_DK);
    b.addDome(top, mathx.normV(top), TOWER_R * 0.20, 7, GILL);
    b.addBlob(v3(0, 0.16, 0), v3(TOWER_R * 0.82, 0.24, TOWER_R * 0.76), 3, 9, STIPE_DK);
    return b.toModel(shader);
}

pub const ARCH_SPAN: f32 = 6.6;
pub const ARCH_H: f32 = 5.4;

/// **AN ARCH NOBODY GREW ON PURPOSE** — two stalks that leant into each other and fused, with a fan of gills
/// hanging under the join. The rib arch is a semicircle solved from one shaft; this is two straight leans
/// meeting at a knuckle, which is what keeps the two structures from reading as the same idea twice.
pub fn hyphaArchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF0AA);
    b.setMat(.plant);
    const half = ARCH_SPAN * 0.5;
    const crown = v3(0, ARCH_H, 0);
    for ([_]f32{ -1.0, 1.0 }) |sd| {
        const foot = v3(sd * half, 0, rng.signed() * 0.25);
        const knee = v3(sd * half * 0.72, ARCH_H * 0.52, rng.signed() * 0.20);
        b.addBlob(v3(foot.x, 0.20, foot.z), v3(0.72, 0.28, 0.66), 3, 8, STIPE_DK);
        b.addCapsule(foot, knee, 0.46, 0.34, 9, art.weathered(STIPE_DK, STIPE, 0.2));
        b.addCapsule(knee, crown, 0.34, 0.26, 9, art.weathered(STIPE, CAP_RIM, 0.7));
    }
    b.addBlob(crown, v3(0.66, 0.44, 0.58), 4, 9, CAP_FLESH_DK);
    b.addBlob(v3(0, ARCH_H + 0.22, 0), v3(0.44, 0.26, 0.40), 3, 8, CAP_FLESH);
    gillsInto(&b, 0, 0, 0.78, ARCH_H - 0.30, 0.34, 16, GILL);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.8, half * 1.3);
        const r = rng.range(0.10, 0.22);
        b.addBlob(v3(mathx.cosf(a) * d, r * 0.6, mathx.sinf(a) * d), v3(r, r * 1.4, r), 3, 6, SPORE_GLOW);
    }
    return b.toModel(shader);
}

pub const CLUSTER_GLOW_H: f32 = 1.55;
pub const CLUSTER_LIGHT_Y: f32 = 1.05;

/// **A KNOT OF LIT CAPS.** Where `glowcap` is one lamp on a stalk, this is a fistful low to the ground — the
/// thing you sow along a path so the floor is legible without a torch.
pub fn glowClusterMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF0AB);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.05, 0.62);
        const h = rng.range(0.45, CLUSTER_GLOW_H);
        capInto(&b, &rng, .{
            .h = h,
            .capR = h * rng.range(0.34, 0.52),
            .drop = h * 0.20,
            .stipeR = h * 0.075,
            .lean = rng.range(6.0, 26.0),
            .gills = 9 + rng.intn(5),
            .glow = true,
            .flesh = art.BLOOM_GLOW,
            .fleshDk = CAP_FLESH_DK,
            .rim = art.BLOOM_CORE,
        }, mathx.cosf(a) * d, mathx.sinf(a) * d, rng.angle());
    }
    b.setMat(.plant);
    return b.toModel(shader);
}

pub const LAMP_H: f32 = 4.2;
pub const LAMP_LIGHT_Y: f32 = 3.0;

/// **A STALK THAT ARCS OVER AND HANGS A LIGHT OFF ITS END.** The tallest lamp in the kingdom and the only
/// one above head height, so it lights the ground rather than your knees. The bulb hangs BELOW the arc —
/// nothing living hangs a weight on a straight stem.
pub fn lampStalkMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF0AC);
    b.setMat(.plant);
    const N = 8;
    var prev = v3(0, 0, 0);
    var a = mathx.radians(6.0);
    const dA = mathx.radians(74.0) / N;
    const step = LAMP_H / N;
    var i: i32 = 0;
    while (i < N) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / N;
        const dir = v3(mathx.sinf(a), mathx.cosf(a), 0);
        const next = mathx.addV(prev, mathx.scaleV(dir, step));
        b.addCapsule(prev, next, mathx.lerpF(0.20, 0.075, t), mathx.lerpF(0.20, 0.075, t + 1.0 / @as(f32, N)), 8, art.weathered(STIPE_DK, STIPE, t));
        prev = next;
        a += dA;
    }
    const hang = v3(prev.x, prev.y - 0.46, prev.z);
    b.addCapsule(prev, hang, 0.045, 0.035, 5, STIPE_DK);
    b.addBlob(hang, v3(0.34, 0.40, 0.34), 4, 9, art.BLOOM_GLOW);
    b.addBlob(v3(hang.x, hang.y + 0.06, hang.z), v3(0.20, 0.24, 0.20), 3, 7, art.BLOOM_CORE);
    b.addBlob(v3(0, 0.16, 0), v3(0.46, 0.20, 0.42), 3, 8, STIPE_DK);
    var s: i32 = 0;
    while (s < 5) : (s += 1) {
        const ang = rng.angle();
        const d = rng.range(0.15, 0.65);
        const r = rng.range(0.020, 0.045);
        b.addBlob(v3(hang.x + mathx.cosf(ang) * d, hang.y - rng.range(0.1, 0.7), hang.z + mathx.sinf(ang) * d), v3(r, r, r), 2, 5, SPORE_GLOW);
    }
    return b.toModel(shader);
}

pub const FOLD_H: f32 = 1.35;
pub const FOLD_L: f32 = 3.4;

/// **A FOLDED MASS ON THE GROUND, AND IT IS NOT A MUSHROOM AT ALL.** Overlapping lobes packed along a
/// wandering seam, like a morel laid flat — the region's one thing with no stalk, no cap and no symmetry,
/// which is what stops the kingdom reading as a single shape at nine sizes.
pub fn fleshFoldMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF0AD);
    b.setMat(.plant);
    const N = 9;
    var x: f32 = -FOLD_L * 0.45;
    var z: f32 = 0;
    var i: i32 = 0;
    while (i < N) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / (N - 1);
        // The seam WANDERS: a row of lobes on a straight line is a caterpillar.
        z += rng.signed() * 0.34;
        const swell = mathx.sinf(t * std.math.pi);
        const r = (0.42 + 0.46 * swell) * rng.range(0.88, 1.12);
        const h = FOLD_H * (0.34 + 0.66 * swell);
        b.addBlob(v3(x, h * 0.45, z), v3(r, h * 0.55, r * rng.range(0.8, 1.25)), 4, 9, art.weathered(art.FLESH_PINK_DK, art.FLESH_PINK, swell));
        // …and every lobe is CREASED, which is the whole read: a fold, not a boulder.
        b.addBlob(v3(x + rng.signed() * 0.12, h * 0.86, z + rng.signed() * 0.12), v3(r * 0.30, h * 0.20, r * 0.86), 3, 7, art.FLESH_PINK_DK);
        b.addBlob(v3(x, h * 0.30, z), v3(r * 1.06, h * 0.16, r * 0.62), 2, 8, art.FLESH_PINK);
        x += r * rng.range(0.72, 0.96);
    }
    var g: i32 = 0;
    while (g < 6) : (g += 1) {
        const a = rng.angle();
        const d = rng.range(0.9, 2.2);
        const r = rng.range(0.025, 0.055);
        b.addBlob(v3(mathx.cosf(a) * d, r * 1.4, mathx.sinf(a) * d), v3(r, r * 1.6, r), 2, 5, art.BLOOM_GLOW);
    }
    return b.toModel(shader);
}

pub const VENT_H: f32 = 3.6;

/// **A CHIMNEY THAT BREATHES.** Stacked collars of fused hyphae with a dark throat and a lit gullet. A
/// cylinder is CAPLESS and this one is supposed to be — the mouth is the point, so it is ringed rather than
/// domed, and the glow sits BELOW the rim so you have to walk up to it to see the light.
pub fn sporeVentMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF0AE);
    b.setMat(.plant);
    const N = 7;
    var y: f32 = 0;
    var cx: f32 = 0;
    var cz: f32 = 0;
    const lean = rng.angle();
    var i: i32 = 0;
    while (i < N) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / (N - 1);
        const r = mathx.lerpF(0.95, 0.44, t) * rng.range(0.94, 1.06);
        // Collars stack thinner as the throat narrows, so the stack tapers in TWO ways, not one.
        const h = VENT_H / N * mathx.lerpF(1.24, 0.72, t);
        b.addCylinder(v3(cx, y, cz), v3(cx, y + h, cz), r, r * 0.93, 11, art.weathered(art.FLESH_PINK_DK, PUNK_DK, t));
        b.addBlob(v3(cx, y + h * 0.5, cz), v3(r * 1.09, h * 0.26, r * 1.09), 2, 11, art.weathered(STIPE_DK, art.FLESH_PINK_DK, t));
        y += h;
        cx += mathx.cosf(lean) * 0.055 + rng.signed() * 0.045;
        cz += mathx.sinf(lean) * 0.055 + rng.signed() * 0.045;
    }
    // The throat is OPEN — a vent that is capped is a chimney pot. The glow sits down inside it.
    b.addCylinder(v3(cx, y - 0.30, cz), v3(cx, y + 0.16, cz), 0.40, 0.46, 12, PUNK_DK);
    b.addBlob(v3(cx, y - 0.30, cz), v3(0.33, 0.14, 0.33), 3, 10, art.BLOOM_GLOW);
    b.addBlob(v3(cx, y - 0.44, cz), v3(0.19, 0.15, 0.19), 3, 8, art.BLOOM_CORE);
    b.addBlob(v3(0, 0.14, 0), v3(1.25, 0.20, 1.18), 3, 9, art.FLESH_PINK_DK);
    var s: i32 = 0;
    while (s < 7) : (s += 1) {
        const a = rng.angle();
        const d = rng.range(0.1, 0.5);
        const r = rng.range(0.030, 0.062);
        b.addBlob(v3(cx + mathx.cosf(a) * d, y + rng.range(0.22, 1.15), cz + mathx.sinf(a) * d), v3(r, r, r), 2, 5, SPORE_GLOW);
    }
    return b.toModel(shader);
}

pub const VEIN_R: f32 = 2.1;

/// Ground cover, and the region's cheapest light: mycelial cord running over the floor, emissive, with no
/// `LightSpec` at all. Sown by the hundred where sixteen real lights is the whole budget.
pub fn glowVeinMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF0AF);
    b.setMat(.plant);
    var run: i32 = 0;
    while (run < 4) : (run += 1) {
        var a = rng.angle();
        var p = v3(rng.signed() * 0.4, 0.03, rng.signed() * 0.4);
        var seg: i32 = 0;
        while (seg < 7) : (seg += 1) {
            a += rng.signed() * 0.7;
            const len = rng.range(0.22, 0.46);
            const q = v3(p.x + mathx.cosf(a) * len, 0.03, p.z + mathx.sinf(a) * len);
            if (mathx.lenXZ(q) > VEIN_R) break;
            const r = rng.range(0.022, 0.045);
            b.addCapsule(p, q, r, r * 0.85, 5, if (rng.float() < 0.55) art.BLOOM_GLOW else SPORE_GLOW);
            if (rng.float() < 0.3) b.addBlob(q, v3(r * 2.2, r * 1.6, r * 2.2), 2, 6, art.BLOOM_CORE);
            p = q;
        }
    }
    return b.toModel(shader);
}

test "THE KINGDOM IS FOUR CANOPY SILHOUETTES AND THREE KINDS OF LIGHT, not one shape at nine sizes" {
    // The colossal one is a landmark: it must clear the others by enough that you navigate by it.
    try std.testing.expect(capTop(GIANT_COLOSSAL) > capTop(GIANT_TALL) * 1.6);
    // …and you still walk under every one of them.
    inline for (.{ GIANT_BROAD, GIANT_TALL, GIANT_TABLE, GIANT_COLOSSAL }) |sp| {
        try std.testing.expect(sp.h - sp.drop * 1.35 > 2.2);
    }
    // Three lamps at three heights, so the floor is lit from knee, chest and overhead rather than one band.
    try std.testing.expect(CLUSTER_LIGHT_Y < GLOW_LIGHT_Y);
    try std.testing.expect(GLOW_LIGHT_Y < LAMP_LIGHT_Y);
    try std.testing.expect(LAMP_LIGHT_Y > 1.8); // over a man's head, which is the whole point of it
    // The two structures are not the same idea twice: one is a column, one is a span.
    try std.testing.expect(TOWER_H > ARCH_H);
    try std.testing.expect(ARCH_SPAN > TOWER_R * 2.0);
}


// ── THE FLOOR OF THE KINGDOM ────────────────────────────────────────────────────────────────────────────
//
// Caps and towers are what you see across the hollow; these are what is under your boots on the way there.
// **A REGION OWES THREE LAYERS AND THE LOWEST ONE IS THE EASIEST TO SKIP** — the canopy got nine props and
// the floor got two, which is why the mycelian photographed as furniture standing on a lawn.
//
// Four of them, and they are four different HABITS rather than four sizes: a sphere, a spike, a crust and a
// shelf. Nothing here is a small mushroom, because a small mushroom is what `mushrooms` already is.

pub const PUFF_R: f32 = 0.62;

/// SPHERES, and one of them has GONE. A clutch of puffballs where the biggest has split and is venting —
/// the burst one is the whole prop, because eight intact spheres is a bag of marbles.
pub fn puffballsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF0FF1);
    b.setMat(.plant);
    const RS = [_]f32{ 1.00, 0.58, 0.74, 0.41, 0.66, 0.33, 0.50 };
    for (RS, 0..) |k, i| {
        const a = @as(f32, @floatFromInt(i)) * 1.29 + rng.signed() * 0.24;
        const d = if (i == 0) 0.0 else rng.range(0.16, 0.46);
        const r = 0.26 * k;
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const burst = i == 0;
        // A puffball sits ON the ground, squashed — a sphere with its equator at ground level is a marble.
        const squash: f32 = if (burst) 0.72 else 0.86;
        b.addBlob(v3(x, r * 0.78, z), v3(r, r * squash, r * rng.range(0.9, 1.1)), 3, 9, art.weathered(CAP_FLESH_DK, CAP_FLESH, 0.5));
        if (burst) {
            // The crater, and the puff coming out of it. Emissive, so it reads in the dark.
            b.addBlob(v3(x, r * 1.28, z), v3(r * 0.52, r * 0.30, r * 0.52), 3, 8, art.BLOOM_CORE);
            var s: i32 = 0;
            while (s < 6) : (s += 1) {
                const sa = rng.angle();
                const sd = rng.range(0.02, r * 0.7);
                const sr = rng.range(0.020, 0.045);
                b.addBlob(v3(x + mathx.cosf(sa) * sd, r * 1.5 + rng.range(0, 0.34), z + mathx.sinf(sa) * sd), v3(sr, sr, sr), 2, 5, SPORE_GLOW);
            }
        } else b.addBlob(v3(x, r * 1.42, z), v3(r * 0.30, r * 0.16, r * 0.30), 2, 7, STIPE_DK);
    }
    return b.toModel(shader);
}

pub const FINGER_H: f32 = 0.54;

/// SPIKES. Dead men's fingers: blunt black clubs pushing straight up out of the litter, pale only at the
/// very tip. **NOT POINTED** — nothing dead in this game ends in a point (AGENTS.md), and a club that
/// tapers to nothing is a spike anyway, which reads as a hazard.
pub fn deadFingersMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xF17E5);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 9) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0, 0.30) * @sqrt(rng.float());
        const h = FINGER_H * rng.range(0.42, 1.0);
        const r = rng.range(0.028, 0.050);
        const lean = rng.range(0.02, 0.22);
        const la = rng.angle();
        const top = v3(mathx.cosf(a) * d + mathx.cosf(la) * h * lean, h, mathx.sinf(a) * d + mathx.sinf(la) * h * lean);
        b.addCylinder(v3(mathx.cosf(a) * d, 0, mathx.sinf(a) * d), top, r * 1.25, r * 0.92, 6, art.CHAR);
        b.addBlob(top, v3(r * 1.15, r * 1.5, r * 1.15), 2, 6, if (rng.float() < 0.45) art.CHAR_LT else art.BONE_DK);
    }
    return b.toModel(shader);
}

pub const CRUST_R: f32 = 1.35;

/// A CRUST. Encrusting fungus spreading flat over the ground in wrinkled lobes — the one thing here with no
/// height at all, and the layer that makes the other three look like they grew out of something.
pub fn crustFungusMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0xC2057);
    b.setMat(.plant);
    var i: i32 = 0;
    while (i < 26) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0, CRUST_R * 0.86) * @sqrt(rng.float());
        const r = rng.range(0.13, 0.34) * (1.0 - d / (CRUST_R * 1.6));
        // Lobes THIN toward the rim, so the patch has an edge instead of a wall.
        b.addBlob(
            v3(mathx.cosf(a) * d, rng.range(0.015, 0.055), mathx.sinf(a) * d),
            v3(r, rng.range(0.012, 0.034), r * rng.range(0.7, 1.3)),
            3,
            7,
            art.weathered(art.FLESH_PINK_DK, art.FLESH_PINK, rng.float()),
        );
    }
    var g: i32 = 0;
    while (g < 5) : (g += 1) {
        const a = rng.angle();
        const d = rng.range(0.1, CRUST_R * 0.55);
        b.addBlob(v3(mathx.cosf(a) * d, 0.055, mathx.sinf(a) * d), v3(0.05, 0.030, 0.05), 2, 6, art.BLOOM_GLOW);
    }
    return b.toModel(shader);
}

pub const SHELF_H: f32 = 1.15;

/// A SHELF, CLIMBING. Brackets up a rotted stub, each one WIDER than the one above it — that is what a real
/// shelf fungus does and it is also what makes the stack read as a staircase rather than a stack of discs.
pub fn shelfStackMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(0x5431F);
    b.setMat(.plant);
    b.addCylinder(v3(0, 0, 0), v3(rng.signed() * 0.10, SHELF_H, rng.signed() * 0.10), 0.16, 0.10, 9, BARK_OLD);
    b.addBlob(v3(0, SHELF_H, 0), v3(0.11, 0.05, 0.11), 2, 8, art.CHAR);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / 6.0;
        const y = 0.14 + SHELF_H * 0.80 * t;
        const out = mathx.lerpF(0.46, 0.19, t) * rng.range(0.86, 1.14);
        const a = @as(f32, @floatFromInt(i)) * 2.31 + rng.signed() * 0.35;
        const cx = mathx.cosf(a) * out * 0.5;
        const cz = mathx.sinf(a) * out * 0.5;
        b.addBlob(v3(cx, y, cz), v3(out * 0.62, 0.032, out * 0.52), 3, 9, art.weathered(CAP_FLESH_DK, CAP_RIM, t));
        // The pale underside — a bracket seen from below is the only white in the palette.
        b.addBlob(v3(cx, y - 0.030, cz), v3(out * 0.52, 0.016, out * 0.44), 3, 8, GILL);
    }
    return b.toModel(shader);
}

test "THE FLOOR IS FOUR HABITS, NOT FOUR SIZES — a sphere, a spike, a crust and a shelf" {
    std.debug.print("\n  floor: puffballs {d:.2} m across, fingers {d:.2} m up, crust {d:.2} m across, shelf {d:.2} m up\n", .{ PUFF_R * 2, FINGER_H, CRUST_R * 2, SHELF_H });
    // The crust is the WIDEST and the flattest; the shelf is the tallest. Neither is the other's scale.
    try std.testing.expect(CRUST_R > PUFF_R);
    try std.testing.expect(SHELF_H > FINGER_H * 2.0);
    // Every one of them is understorey — none reaches the giant caps' stipe clearance.
    try std.testing.expect(SHELF_H < GIANT_BROAD.h - GIANT_BROAD.drop * 1.35);
}
