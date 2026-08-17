const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

pub const STONE = rgba(58, 55, 49, 255); // ruin masonry: ochre-grey mineral, not builders' slab
pub const STONE_LT = rgba(73, 70, 62, 255);
pub const STONE_DK = rgba(38, 36, 32, 255);
pub const STONE_MOSS = rgba(52, 58, 40, 255);
pub const MORTAR = rgba(36, 33, 29, 255);
pub const MARBLE = rgba(54, 54, 52, 255);
pub const MARBLE_LT = rgba(70, 70, 68, 255); // capitals, abaci, an altar top
pub const MARBLE_DK = rgba(34, 34, 34, 255); // in shade, or where the soot and rain got in
// Living rock — and the three tones separate on HUE, not value alone: the noon sun flattens any value
// pair on a face this big (AGENTS.md), so as three neutral greys every cliff came back one slab of pale
// concrete. Warm base, COOL shadow seams, buff caught-light — the strata banding the builder already
// deals only reads at all because these disagree in hue.
pub const CLIFF_ROCK = rgba(46, 42, 36, 255);
pub const CLIFF_DK = rgba(27, 27, 29, 255);
pub const CLIFF_LT = rgba(56, 51, 42, 255);
pub const ROCK_DEEP = rgba(23, 22, 21, 255);
pub const PAVE = rgba(32, 31, 27, 255);
pub const PAVE_DK = rgba(22, 21, 19, 255);
pub const PAVE_LT = rgba(41, 40, 35, 255); // the crown of a sett, worn smooth by feet and cartwheels
pub const SOIL = rgba(28, 23, 17, 255); // the dirt showing through where the road has lost its stones
pub const BARK = rgba(36, 29, 22, 255);
pub const BARK_DK = rgba(26, 21, 17, 255);
pub const BARK_LIVE = rgba(44, 36, 27, 255); // a living trunk reads a touch warmer than a dead one
pub const BARK_OLD = rgba(22, 17, 13, 255);
pub const IRON = rgba(30, 28, 26, 255);
pub const STEEL = rgba(100, 106, 116, 255);
pub const BRASS = rgba(122, 92, 40, 255);
pub const TIMBER = rgba(48, 37, 25, 255);
pub const TIMBER_DK = rgba(33, 26, 18, 255);
pub const SPRUCE = rgba(59, 46, 30, 255);
pub const THATCH = rgba(74, 60, 30, 255);
pub const THATCH_DK = rgba(52, 42, 22, 255);
pub const EMBER = rgba(252, 184, 80, 14);
pub const WISP = rgba(250, 196, 110, 120);
// Eased DOWN across the board (owner: all flames a bit more subtle).
pub const FLAME_CORE = rgba(226, 190, 128, 25); // pale heart of a torch — no longer near-WHITE
pub const FLAME_MID = rgba(214, 138, 48, 40);
pub const FLAME_TIP = rgba(176, 82, 24, 90); // the cooler tongue — and now the most transparent of them
pub const COAL = rgba(196, 78, 22, 70);
pub const SMOKE_HOT = rgba(64, 54, 46, 255);
pub const SMOKE_MID = rgba(58, 55, 52, 255);
pub const SMOKE_COLD = rgba(52, 52, 55, 255);
pub const CLOTH = rgba(76, 20, 12, 255); // faded war-banner crimson (matches the hero's cape)
pub const CLOTH_DK = rgba(48, 14, 10, 255);
pub const CLOTH_SUN = rgba(96, 46, 32, 255);
pub const CANVAS = rgba(42, 36, 28, 255);

pub const GRASS_GOLD = rgba(96, 76, 34, 255);
pub const GRASS_DRY = rgba(78, 64, 30, 255);
pub const GRASS_GRN = rgba(50, 56, 28, 255);
pub const SCRUB = rgba(38, 46, 26, 255);
pub const SCRUB_DK = rgba(28, 34, 20, 255);
pub const STEM = rgba(44, 54, 28, 255);
pub const PETAL = rgba(210, 196, 152, 255);
pub const SEED = rgba(118, 94, 46, 255);
pub const PETAL_GLOW = rgba(242, 206, 118, 200); // slight emissive — kin to the bonfire ember
// The leaf family spans a real HUE range now, not one olive at five values: the canopy builders already
// put light on top and dark below, but sun-flattened value was all that said so — the undersides go COOL
// blue-green and the crowns warm lime, which is the split daylight cannot take away.
pub const LEAF_DK = rgba(19, 32, 24, 255);
pub const LEAF = rgba(35, 46, 25, 255);
pub const LEAF_LT = rgba(55, 58, 25, 255);
pub const LEAF_GOLD = rgba(74, 66, 30, 255);
pub const LEAF_PALE = rgba(58, 64, 34, 255); // willow: silvered, thirstier green
pub const BERRY = rgba(58, 14, 18, 255);
pub const LEAF_DAMP = rgba(23, 40, 31, 255); // shade-grown: properly COOL beside the sunlit gold
pub const CLOVER_GRN = rgba(40, 54, 30, 255);
pub const MOSS_SOFT = rgba(44, 56, 32, 255);
pub const MOSS_DK = rgba(30, 40, 24, 255);
pub const BRACKEN_BRN = rgba(50, 35, 19, 255);
pub const NETTLE = rgba(34, 48, 26, 255);
pub const PURPLE = rgba(72, 44, 76, 255); // thistle / foxglove / heather bloom
pub const PURPLE_DK = rgba(50, 30, 56, 255);
pub const GORSE_GOLD = rgba(126, 100, 28, 255); // the only genuinely bright flower out here
pub const PETAL_WHITE = rgba(196, 190, 168, 255);
pub const PETAL_BLUE = rgba(96, 108, 140, 255);
pub const CAP_BROWN = rgba(88, 60, 40, 255); // mushroom cap
pub const CAP_PALE = rgba(126, 116, 96, 255);
pub const LILY_GRN = rgba(46, 60, 34, 255);
pub const IVY_GRN = rgba(28, 40, 24, 255);
pub const NEEDLE = rgba(21, 32, 27, 255); // conifer: the darkest green in the world, and COOL
pub const NEEDLE_LT = rgba(37, 45, 25, 255); // …against warm lit tips — hue carries what the sun flattens
pub const NEEDLE_DK = rgba(15, 24, 21, 255); // the inner shade the lower whorls grow in
pub const BIRCH_BARK = rgba(104, 100, 90, 255); // pale, and the only tree you can pick out at distance
pub const BIRCH_SCAR = rgba(44, 42, 38, 255);
pub const BONE = rgba(108, 104, 92, 255);
pub const RUST = rgba(58, 38, 24, 255);
// BONFIRE ASH — the palest albedo in the world, and deliberately so.
pub const ASH = rgba(78, 74, 70, 255);
pub const ASH_LT = rgba(96, 92, 86, 255); // where it has been raked over, or a fresh drift
pub const ASH_DK = rgba(46, 43, 40, 255); // wet, or trodden into the kerb
pub const WATER_DEEP = rgba(13, 19, 21, 255);
pub const WATER_MID = rgba(18, 25, 26, 255);
pub const WATER_SHALLOW = rgba(30, 35, 31, 255);
pub const WATER_MUD = rgba(40, 35, 25, 255); // the wet margin the sheet sits in

pub const Part = struct { ax: f32 = 0, az: f32 = 0, bx: f32 = 0, bz: f32 = 0, r: f32, h: f32 };

pub const TOWER_R: f32 = 2.35; // wall centre-line radius
pub const TOWER_SIDES: i32 = 14;
pub const TOWER_DOOR: i32 = 3; // masonry columns omitted for the door, centred on local −Z (index 0)
pub const towerRing = blk: {
    var out: [TOWER_SIDES - TOWER_DOOR]Part = undefined;
    var n: usize = 0;
    for (0..TOWER_SIDES) |i| {
        if (towerDoorway(@intCast(i))) continue;
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, TOWER_SIDES);
        out[n] = .{ .ax = @sin(a) * TOWER_R, .az = -@cos(a) * TOWER_R, .bx = @sin(a) * TOWER_R, .bz = -@cos(a) * TOWER_R, .r = 0.62, .h = 11.0 };
        n += 1;
    }
    std.debug.assert(n == out.len);
    break :blk out;
};

pub fn towerDoorway(i: i32) bool {
    const half = @divTrunc(TOWER_DOOR, 2);
    return @mod(i + half, TOWER_SIDES) < TOWER_DOOR;
}


// PACKED STONE HAS A CORE (owner's law).

/// A run of coursed masonry from (ax,az) to (bx,bz).
pub const Course = struct {
    thick: f32,
    height: f32,
    courses: i32 = 9,
    blockW: f32 = 0.72, // nominal block length along the run
    crumbleTop: f32 = 0.45, // the top two courses have not been pointed in three centuries
    crumble: f32 = 0.04,
    gapLo: f32 = 9, // no opening by default (the run is only ever a few metres)
    gapHi: f32 = 9,
    sillY: f32 = 0,
    headY: f32 = 0,
    core: f32 = 0.80, // substrate thickness as a fraction of `thick` (0 = facing only)
};


pub fn courseInto(bb: *Builder, r: *mathx.Rng, ax: f32, az: f32, bx: f32, bz: f32, spec: Course) void {
    bb.setMat(.stone);
    const dx = bx - ax;
    const dz = bz - az;
    const runLen = @sqrt(dx * dx + dz * dz);
    const ux = dx / runLen;
    const uz = dz / runLen;
    const ch = spec.height / @as(f32, @floatFromInt(spec.courses));
    if (spec.core > 0.001) {
        var c: i32 = 0;
        while (c < spec.courses) : (c += 1) {
            const y0 = @as(f32, @floatFromInt(c)) * ch;
            const yc = y0 + ch * 0.5;
            const open = yc > spec.sillY and yc < spec.headY;
            const lo: f32 = if (open) spec.gapLo else runLen * 0.5;
            const hi: f32 = if (open) spec.gapHi else runLen * 0.5;
            const spans = [2][2]f32{ .{ -runLen * 0.5, @min(lo, runLen * 0.5) }, .{ @max(hi, -runLen * 0.5), runLen * 0.5 } };
            for (spans, 0..) |sp, si| {
                if (si == 1 and !open) break; // one span covers it when there is no opening here
                const w = sp[1] - sp[0];
                if (w <= 0.02) continue;
                const mid = (sp[0] + sp[1]) * 0.5;
                bb.addBox(
                    v3(ax + ux * (runLen * 0.5 + mid), yc, az + uz * (runLen * 0.5 + mid)),
                    v3(ux * w * 0.5, 0, uz * w * 0.5),
                    v3(0, ch * 0.56, 0),
                    v3(-uz * spec.thick * spec.core, 0, ux * spec.thick * spec.core),
                    MORTAR,
                );
            }
        }
    }
    var c: i32 = 0;
    while (c < spec.courses) : (c += 1) {
        const yc = @as(f32, @floatFromInt(c)) * ch + ch * 0.5;
        const crumble: f32 = if (c >= spec.courses - 2) spec.crumbleTop else spec.crumble;
        const nb: i32 = @intFromFloat(@max(runLen / spec.blockW, 2.0));
        var i: i32 = 0;
        while (i < nb) : (i += 1) {
            const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(nb));
            const s = (t - 0.5) * runLen; // signed distance along the run from its centre
            if (s > spec.gapLo and s < spec.gapHi and yc > spec.sillY and yc < spec.headY) continue; // the opening
            if (r.float() < crumble) continue;
            const bw = (runLen / @as(f32, @floatFromInt(nb))) * r.range(1.20, 1.50); // BEDDED, not butted
            const col = if (r.float() < 0.15) STONE_LT else if (r.float() < 0.32) STONE_DK else STONE;
            bb.addBox(
                v3(ax + ux * (t * runLen) + r.signed() * 0.016, yc, az + uz * (t * runLen) + r.signed() * 0.016),
                v3(ux * bw * 0.5, r.signed() * 0.006, uz * bw * 0.5),
                v3(r.signed() * 0.010, ch * 0.54 * r.range(1.0, 1.06), r.signed() * 0.010),
                v3(-uz * spec.thick, 0, ux * spec.thick),
                col,
            );
        }
    }
}

pub fn courseStack(bb: *Builder, r: *mathx.Rng, cx: f32, y0: f32, cz: f32, w: f32, d: f32, ch: f32, n: i32, taper: f32) f32 {
    bb.setMat(.stone);
    const total = ch * @as(f32, @floatFromInt(n));
    bb.addCube(v3(cx, y0 + total * 0.5, cz), v3(w * (1.0 - taper * 0.5) * 0.94, total, d * (1.0 - taper * 0.5) * 0.94), MORTAR); // the core
    var y = y0;
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
        const sw = w * (1.0 - taper * t) * r.range(0.99, 1.014);
        const sd = d * (1.0 - taper * t) * r.range(0.99, 1.014);
        const h = ch * r.range(1.0, 1.08); // courses OVERLAP
        bb.addBox(
            v3(cx + r.signed() * 0.026, y + h * 0.45, cz + r.signed() * 0.026),
            v3(sw * 0.5, r.signed() * 0.008, r.signed() * 0.007),
            v3(0, h * 0.5, 0),
            v3(r.signed() * 0.007, 0, sd * 0.5),
            if (r.float() < (if (@mod(i, 2) == 0) @as(f32, 0.5) else 0.24)) STONE_DK else if (r.float() < 0.16) STONE_LT else STONE,
        );
        y += ch;
    }
    return y;
}

pub fn quoinsInto(bb: *Builder, r: *mathx.Rng, cx: f32, cz: f32, y0: f32, ch: f32, n: i32, big: f32, small: f32) void {
    bb.setMat(.stone);
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const long = @mod(i, 2) == 0;
        const sx = if (long) big else small;
        const sz = if (long) small else big;
        bb.addCube(
            v3(cx, y0 + (@as(f32, @floatFromInt(i)) + 0.5) * ch, cz),
            v3(sx * r.range(0.94, 1.06), ch * r.range(0.86, 0.98), sz * r.range(0.94, 1.06)),
            if (r.float() < 0.3) STONE_LT else STONE,
        );
    }
}

pub fn lichenInto(bb: *Builder, r: *mathx.Rng, c: rl.Vector3, ext: rl.Vector3, n: i32) void {
    bb.setMat(.plant);
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const f = r.range(0.32, 0.66);
        bb.addBlob(
            v3(c.x + r.signed() * ext.x, c.y + r.signed() * ext.y, c.z + r.signed() * ext.z),
            v3(@max(ext.x * f, 0.014), @max(ext.y * f, 0.014), @max(ext.z * f, 0.014)),
            3,
            5,
            if (r.float() < 0.4) MOSS_DK else if (r.float() < 0.7) STONE_MOSS else MOSS_SOFT,
        );
    }
}

pub fn chipsInto(bb: *Builder, r: *mathx.Rng, cx: f32, cz: f32, spread: f32, lo: f32, hi: f32, n: i32) void {
    bb.setMat(.stone);
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const a = r.angle();
        const d = r.range(0.2, 1.0) * spread;
        const rr = r.range(lo, hi);
        bb.addBlob(
            v3(cx + mathx.cosf(a) * d, rr * r.range(0.34, 0.62), cz + mathx.sinf(a) * d),
            v3(rr, rr * r.range(0.48, 0.8), rr * r.range(0.8, 1.3)),
            3,
            5,
            if (r.float() < 0.26) STONE_MOSS else if (r.float() < 0.5) STONE_LT else STONE_DK,
        );
    }
}

pub fn crackInto(bb: *Builder, a: rl.Vector3, dir: rl.Vector3, side: rl.Vector3, len: f32, w: f32, into: f32) void {
    bb.setMat(.stone);
    const nx = dir.y * side.z - dir.z * side.y;
    const ny = dir.z * side.x - dir.x * side.z;
    const nz = dir.x * side.y - dir.y * side.x;
    const nl = @max(@sqrt(nx * nx + ny * ny + nz * nz), 1e-5);
    bb.addBox(
        v3(a.x + dir.x * len * 0.5, a.y + dir.y * len * 0.5, a.z + dir.z * len * 0.5),
        mathx.scaleV(dir, len * 0.5),
        mathx.scaleV(side, w),
        v3(nx / nl * into, ny / nl * into, nz / nl * into),
        STONE_DK,
    );
}

pub fn flameInto(b: *Builder, rng: *mathx.Rng, cx: f32, cy: f32, cz: f32, s: f32) void {
    b.setMat(.flame);
    b.setAnimY(cy);
    b.addBlob(v3(cx, cy + 0.015 * s, cz), v3(0.175 * s, 0.045 * s, 0.175 * s), 3, 9, COAL);
    b.addBlob(v3(cx, cy + 0.055 * s, cz), v3(0.078 * s, 0.048 * s, 0.078 * s), 3, 8, FLAME_CORE);
    var t: i32 = 0;
    while (t < 6) : (t += 1) {
        const a = rng.angle();
        const off = rng.range(0.02, 0.115) * s; // a BROAD base — the lobes sit beside each other
        const h = rng.range(0.17, 0.44) * s; // the tallest tongue sets the flame's height
        const w = rng.range(0.058, 0.100) * s;
        const lean = rng.range(0.01, 0.05) * s;
        const y0 = cy + 0.02 * s;
        const x0 = cx + mathx.cosf(a) * off;
        const z0 = cz + mathx.sinf(a) * off;
        const mx = x0 + mathx.cosf(a) * lean;
        const mz = z0 + mathx.sinf(a) * lean;
        const tx = mx + mathx.cosf(a) * lean * 1.6 + rng.signed() * 0.02 * s;
        const tz = mz + mathx.sinf(a) * lean * 1.6 + rng.signed() * 0.02 * s;
        b.addCapsule(
            v3(x0, y0, z0),
            v3(mx, y0 + h * 0.55, mz),
            w,
            w * 0.82,
            7,
            if (t == 0) FLAME_MID else if (rng.float() < 0.55) FLAME_MID else FLAME_TIP,
        );
        b.addCapsule(v3(mx, y0 + h * 0.52, mz), v3(tx, y0 + h, tz), w * 0.80, w * 0.26, 6, FLAME_TIP);
    }
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const r = rng.range(0.010, 0.022) * s;
        b.addBlob(v3(cx + rng.signed() * 0.16 * s, cy + rng.range(0.30, 0.62) * s, cz + rng.signed() * 0.16 * s), v3(r, r, r), 3, 5, WISP);
    }
    b.setAnimY(0); // sticky, like setMat — hand the Builder back the way it was found
}
pub fn blade(b: *Builder, x: f32, z: f32, h: f32, lx: f32, lz: f32, r: f32, col: rl.Color) void {
    b.addCylinder(v3(x, 0, z), v3(x + lx, h, z + lz), r, 0.003, 4, col);
}

pub fn bladeColor(rng: *mathx.Rng) rl.Color {
    const roll = rng.float();
    if (roll < 0.5) return GRASS_GOLD;
    if (roll < 0.8) return GRASS_DRY;
    return GRASS_GRN;
}

pub fn tuftInto(b: *Builder, rng: *mathx.Rng, cx: f32, cz: f32, s: f32) void {
    // SETS ITS OWN MATERIAL, like every other helper here. It was the one that inherited the caller's, and
    // `propruins.swordMesh` calls it straight after `chipsInto` — so that grass came out tagged `.stone`
    // and took the stone weathering branch in the shader.
    b.setMat(.plant);
    const nb = 6 + rng.intn(3);
    var i: i32 = 0;
    while (i < nb) : (i += 1) {
        const a = rng.angle();
        const rr = rng.range(0.02, 0.10) * s;
        const x = cx + mathx.cosf(a) * rr;
        const z = cz + mathx.sinf(a) * rr;
        const lean = rng.range(0.06, 0.24) * s;
        const la = rng.angle();
        blade(b, x, z, rng.range(0.26, 0.52) * s, mathx.cosf(la) * lean, mathx.sinf(la) * lean, 0.016 * s, bladeColor(rng));
    }
    if (rng.float() < 0.55) {
        const la = rng.angle();
        const lean = rng.range(0.04, 0.12) * s;
        const h = rng.range(0.55, 0.8) * s;
        const tx = cx + mathx.cosf(la) * lean;
        const tz = cz + mathx.sinf(la) * lean;
        blade(b, cx, cz, h, mathx.cosf(la) * lean, mathx.sinf(la) * lean, 0.012 * s, GRASS_DRY);
        b.addCube(v3(tx, h, tz), v3(0.035 * s, 0.09 * s, 0.035 * s), SEED);
    }
}


/// AN ORIENTED FRAME for a flat object: `w` across it, `a` along it, `n` out through its face, with n = w x a.
pub const Frame = struct {
    o: rl.Vector3,
    w: rl.Vector3,
    a: rl.Vector3,
    n: rl.Vector3,
    s: f32 = 1,

    pub fn at(self: Frame, across: f32, along: f32, out: f32) rl.Vector3 {
        const ac = across * self.s;
        const al = along * self.s;
        const ou = out * self.s;
        return v3(
            self.o.x + self.w.x * ac + self.a.x * al + self.n.x * ou,
            self.o.y + self.w.y * ac + self.a.y * al + self.n.y * ou,
            self.o.z + self.w.z * ac + self.a.z * al + self.n.z * ou,
        );
    }
    pub fn ring(self: Frame, across: f32, along: f32, out: f32, r: f32, ang: f32) rl.Vector3 {
        return self.at(across + mathx.cosf(ang) * r, along + mathx.sinf(ang) * r, out);
    }
    pub fn axis(self: Frame, across: f32, along: f32, out: f32) rl.Vector3 {
        const ac = across * self.s;
        const al = along * self.s;
        const ou = out * self.s;
        return v3(
            self.w.x * ac + self.a.x * al + self.n.x * ou,
            self.w.y * ac + self.a.y * al + self.n.y * ou,
            self.w.z * ac + self.a.z * al + self.n.z * ou,
        );
    }
};

/// A FLAT PLATE from a closed outline: `prof` is (along, half-width, half-depth) up the frame's `a` axis, mirrored across `w`.
pub fn plateInto(b: *Builder, fr: Frame, prof: []const [3]f32, face: rl.Color, side: rl.Color) void {
    const back = v3(-fr.n.x, -fr.n.y, -fr.n.z);
    var i: usize = 0;
    while (i + 1 < prof.len) : (i += 1) {
        const t0 = prof[i][0];
        const w0 = prof[i][1];
        const d0 = prof[i][2];
        const t1 = prof[i + 1][0];
        const w1 = prof[i + 1][1];
        const d1 = prof[i + 1][2];
        b.quad(fr.at(-w0, t0, d0), fr.at(w0, t0, d0), fr.at(w1, t1, d1), fr.at(-w1, t1, d1), fr.n, face);
        b.quad(fr.at(-w0, t0, -d0), fr.at(-w1, t1, -d1), fr.at(w1, t1, -d1), fr.at(w0, t0, -d0), back, side);
        const out = mathx.normV(mathx.crossV(mathx.subV(fr.at(w1, t1, 0), fr.at(w0, t0, 0)), fr.n));
        b.quad(fr.at(w0, t0, -d0), fr.at(w1, t1, -d1), fr.at(w1, t1, d1), fr.at(w0, t0, d0), out, side);
        b.quad(fr.at(-w0, t0, -d0), fr.at(-w0, t0, d0), fr.at(-w1, t1, d1), fr.at(-w1, t1, -d1), v3(-out.x, -out.y, -out.z), side);
    }
}

pub fn faceDiscInto(b: *Builder, fr: Frame, across: f32, along: f32, out: f32, r: f32, sides: i32, col: rl.Color) void {
    const c = fr.at(across, along, out);
    const sf: f32 = @floatFromInt(sides);
    var s: i32 = 0;
    while (s < sides) : (s += 2) {
        const a0 = std.math.tau * @as(f32, @floatFromInt(s)) / sf;
        const a1 = std.math.tau * @as(f32, @floatFromInt(s + 1)) / sf;
        const a2 = std.math.tau * @as(f32, @floatFromInt(s + 2)) / sf;
        b.quad(c, fr.ring(across, along, out, r, a0), fr.ring(across, along, out, r, a1), fr.ring(across, along, out, r, a2), fr.n, col);
    }
}

/// THE GUITAR BODY'S OUTLINE, in metres up the instrument's axis from its tail: (along, half-width, half-depth).
const GUITAR_BODY = [_][3]f32{
    .{ 0.000, 0.023, 0.030 },
    .{ 0.024, 0.104, 0.046 },
    .{ 0.058, 0.158, 0.053 },
    .{ 0.104, 0.190, 0.056 },
    .{ 0.152, 0.198, 0.056 }, // lower bout, at its widest
    .{ 0.208, 0.191, 0.055 },
    .{ 0.258, 0.164, 0.053 },
    .{ 0.300, 0.135, 0.051 },
    .{ 0.344, 0.145, 0.049 },
    .{ 0.394, 0.165, 0.047 },
    .{ 0.444, 0.166, 0.045 }, // upper bout
    .{ 0.488, 0.138, 0.043 },
    .{ 0.520, 0.070, 0.042 }, // the heel the neck goes into
};

/// **A GUITAR LEANED AGAINST A ROCK, and the rock it leans on** — the pair, here rather than in one fire's own
/// family file, because BOTH fires you can sit at carry it (owner: "they all should"). A copy per fire is a
/// second place for the lean, the foot offset and the scale to drift, on geometry whose whole point is that
/// the instrument and its rock agree.
pub fn guitarRockInto(b: *Builder, rng: *mathx.Rng, cx: f32, cz: f32) void {
    b.setMat(.stone);
    b.addBlob(v3(cx, 0.22, cz), v3(0.52, 0.235, 0.46), 4, 9, if (rng.float() < 0.4) STONE_MOSS else STONE_DK);
    b.addBlob(v3(cx + rng.signed() * 0.16, 0.30, cz + rng.signed() * 0.16), v3(0.34, 0.115, 0.31), 3, 8, ROCK_DEEP);
    lichenInto(b, rng, v3(cx + rng.signed() * 0.2, 0.40, cz + rng.signed() * 0.2), v3(0.16, 0.015, 0.15), 3);
}

/// …and the instrument stood against it. `scale` is the one thing the two fires differ on: a bonfire camp is a
/// bigger stage than a campfire's ring of stones.
pub fn guitarLeaningInto(b: *Builder, cx: f32, cz: f32, yaw: f32, scale: f32) void {
    const LEAN: f32 = 0.50;
    const FOOT: f32 = 0.70;
    const cy = mathx.cosf(yaw);
    const sy = mathx.sinf(yaw);
    const cl = mathx.cosf(LEAN);
    const sl = mathx.sinf(LEAN);
    guitarInto(b, .{
        .o = v3(cx + cy * FOOT, 0.020, cz + sy * FOOT),
        .w = v3(sy, 0, -cy), // across the strings, level
        .a = v3(-cy * sl, cl, -sy * sl), // up the neck, leaning BACK over the rock
        .n = v3(cy * cl, sl, sy * cl), // out through the soundboard, tipped UP by the lean
        .s = scale,
    });
}

pub fn guitarInto(b: *Builder, fr: Frame) void {
    b.setMat(.wood);
    plateInto(b, fr, &GUITAR_BODY, SPRUCE, TIMBER_DK);
    faceDiscInto(b, fr, 0, 0.330, 0.052, 0.070, 14, BONE);
    faceDiscInto(b, fr, 0, 0.330, 0.054, 0.055, 14, BARK_OLD);
    b.addBox(fr.at(0, 0.128, 0.062), fr.axis(0.058, 0, 0), fr.axis(0, 0.013, 0), fr.axis(0, 0, 0.007), BARK_OLD);
    b.addBox(fr.at(0, 0.132, 0.0715), fr.axis(0.050, 0, 0), fr.axis(0, 0.003, 0), fr.axis(0, 0, 0.0025), BONE);
    b.addBox(fr.at(0, 0.690, 0.026), fr.axis(0.029, 0, 0), fr.axis(0, 0.175, 0), fr.axis(0, 0, 0.016), TIMBER_DK);
    b.addBox(fr.at(0, 0.700, 0.048), fr.axis(0.027, 0, 0), fr.axis(0, 0.165, 0), fr.axis(0, 0, 0.006), BARK_OLD);
    for ([_]f32{ 1, 3, 5, 7, 9 }) |semis| {
        const t = 0.865 - 0.737 * (1.0 - std.math.pow(f32, 2.0, -semis / 12.0));
        b.addBox(fr.at(0, t, 0.0555), fr.axis(0.027, 0, 0), fr.axis(0, 0.0025, 0), fr.axis(0, 0, 0.0015), BONE);
    }
    b.addBox(fr.at(0, 0.868, 0.0555), fr.axis(0.028, 0, 0), fr.axis(0, 0.004, 0), fr.axis(0, 0, 0.004), BONE); // the nut
    const hc = mathx.cosf(0.22);
    const hs = mathx.sinf(0.22);
    const hd = Frame{
        .o = fr.at(0, 0.872, 0.022),
        .w = fr.w,
        .a = mathx.subV(mathx.scaleV(fr.a, hc), mathx.scaleV(fr.n, hs)),
        .n = mathx.addV(mathx.scaleV(fr.n, hc), mathx.scaleV(fr.a, hs)),
        .s = fr.s,
    };
    b.addBox(hd.at(0, 0.072, 0), hd.axis(0.037, 0, 0), hd.axis(0, 0.072, 0), hd.axis(0, 0, 0.012), TIMBER_DK);
    b.setMat(.steel);
    for ([_]f32{ 0.030, 0.072, 0.114 }) |t| {
        b.addCapsule(hd.at(0.030, t, 0), hd.at(0.060, t, 0), 0.005, 0.005, 5, BRASS);
        b.addBox(hd.at(0.072, t, 0), hd.axis(0.011, 0, 0), hd.axis(0, 0.014, 0), hd.axis(0, 0, 0.004), BONE);
    }
    for ([_]f32{ -0.026, 0, 0.026 }, [_]f32{ -0.019, 0, 0.019 }, [_]f32{ 0.030, 0.072, 0.114 }) |low, high, peg| {
        b.addCapsule(fr.at(low, 0.130, 0.0725), fr.at(high, 0.866, 0.058), 0.0022, 0.0022, 4, IRON);
        b.addCapsule(fr.at(high, 0.866, 0.058), hd.at(0.034, peg, 0.006), 0.0022, 0.0022, 4, IRON);
    }
}

