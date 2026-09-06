const std = @import("std");
const rl = @import("raylib");
const gfx = @import("../gfx/gfx.zig");
const mathx = @import("../core/mathx.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

pub const STONE = rgba(58, 55, 49, 255);
pub const STONE_LT = rgba(73, 70, 62, 255);
pub const STONE_DK = rgba(38, 36, 32, 255);
pub const STONE_MOSS = rgba(52, 58, 40, 255);
pub const MORTAR = rgba(36, 33, 29, 255);
pub const MARBLE = rgba(54, 54, 52, 255);
pub const MARBLE_LT = rgba(70, 70, 68, 255);
pub const MARBLE_DK = rgba(34, 34, 34, 255);
pub const CLIFF_ROCK = rgba(46, 42, 36, 255);
pub const CLIFF_DK = rgba(27, 27, 29, 255);
pub const CLIFF_LT = rgba(56, 51, 42, 255);
pub const ROCK_DEEP = rgba(23, 22, 21, 255);
pub const PAVE = rgba(32, 31, 27, 255);
pub const PAVE_DK = rgba(22, 21, 19, 255);
pub const PAVE_LT = rgba(41, 40, 35, 255);
pub const SOIL = rgba(28, 23, 17, 255);
pub const BARK = rgba(36, 29, 22, 255);
pub const BARK_DK = rgba(26, 21, 17, 255);
pub const BARK_LIVE = rgba(44, 36, 27, 255);
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
pub const FLAME_CORE = rgba(226, 190, 128, 25);
pub const FLAME_MID = rgba(214, 138, 48, 40);
pub const FLAME_TIP = rgba(176, 82, 24, 90);
pub const COAL = rgba(196, 78, 22, 70);
pub const SMOKE_HOT = rgba(64, 54, 46, 255);
pub const SMOKE_MID = rgba(58, 55, 52, 255);
pub const SMOKE_COLD = rgba(52, 52, 55, 255);
pub const CLOTH = rgba(76, 20, 12, 255);
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
pub const PETAL_GLOW = rgba(242, 206, 118, 200);
pub const LEAF_DK = rgba(19, 32, 24, 255);
pub const LEAF = rgba(35, 46, 25, 255);
pub const LEAF_LT = rgba(55, 58, 25, 255);
pub const LEAF_GOLD = rgba(74, 66, 30, 255);
pub const LEAF_PALE = rgba(58, 64, 34, 255);
pub const BERRY = rgba(58, 14, 18, 255);
pub const LEAF_DAMP = rgba(23, 40, 31, 255);
pub const CLOVER_GRN = rgba(40, 54, 30, 255);
pub const MOSS_SOFT = rgba(44, 56, 32, 255);
pub const MOSS_DK = rgba(30, 40, 24, 255);
pub const BRACKEN_BRN = rgba(50, 35, 19, 255);
pub const NETTLE = rgba(34, 48, 26, 255);
pub const PURPLE = rgba(72, 44, 76, 255);
pub const PURPLE_DK = rgba(50, 30, 56, 255);
pub const GORSE_GOLD = rgba(126, 100, 28, 255);
pub const PETAL_WHITE = rgba(196, 190, 168, 255);
pub const PETAL_BLUE = rgba(96, 108, 140, 255);
pub const CAP_BROWN = rgba(88, 60, 40, 255);
pub const CAP_PALE = rgba(126, 116, 96, 255);
pub const LILY_GRN = rgba(46, 60, 34, 255);
pub const IVY_GRN = rgba(28, 40, 24, 255);
pub const NEEDLE = rgba(21, 32, 27, 255);
pub const NEEDLE_LT = rgba(37, 45, 25, 255);
pub const NEEDLE_DK = rgba(15, 24, 21, 255);
pub const BIRCH_BARK = rgba(104, 100, 90, 255);
pub const BIRCH_SCAR = rgba(44, 42, 38, 255);
pub const BONE = rgba(108, 104, 92, 255);
// GREAT BONE IS NOT SCATTERED BONE: a rib nine metres tall is a BIG SMOOTH MASS, and at albedo 108 the key and the gamma lift bring it back at 221/255. 60 comes back at 172, and NEUTRAL.
pub const BONE_OLD = rgba(44, 45, 41, 255);
pub const BONE_LT = rgba(58, 59, 53, 255);
pub const BONE_DK = rgba(28, 29, 27, 255);
pub const MARROW = rgba(70, 63, 50, 255);
// CHARCOAL IS THE DARKEST ALBEDO IN THE WORLD and has to be: a burnt spar is a tall smooth mass. 18 lands at 98/255 on screen.
pub const CHAR = rgba(18, 16, 15, 255);
pub const CHAR_LT = rgba(30, 27, 24, 255);
pub const EMBER_LIVE = rgba(198, 92, 26, 60);
pub const CINDER_GREY = rgba(46, 42, 39, 255);
// A DRIFT IS NOT THE CAMPFIRE'S ASH: `ASH`/`ASH_LT` are a handful in a hearth, and a two-metre dune at 96 came back at 214/255. Same material solved for the size it is drawn at.
pub const DRIFT = rgba(54, 50, 47, 255);
pub const DRIFT_LT = rgba(70, 66, 62, 255);
pub const DRIFT_DK = rgba(37, 34, 32, 255);
pub const PUNK = rgba(66, 54, 36, 255);
pub const PUNK_DK = rgba(42, 34, 23, 255);
pub const CAP_FLESH = rgba(44, 35, 40, 255);
pub const CAP_FLESH_DK = rgba(29, 23, 28, 255);
pub const CAP_RIM = rgba(58, 46, 50, 255);
pub const GILL = rgba(104, 96, 88, 255);
pub const STIPE = rgba(72, 66, 58, 255);
pub const STIPE_DK = rgba(46, 42, 37, 255);
pub const SPORE_GLOW = rgba(150, 206, 198, 120);
pub const CAP_GLOW = rgba(96, 168, 160, 150);
// The warm half of the Mycelian's light. Alpha is EMISSIVE, so these are how bright they burn, not how see-through they are — and a low number is a strong glow.
pub const BLOOM_GLOW = rgba(206, 112, 158, 105);
pub const BLOOM_CORE = rgba(236, 172, 200, 70);
pub const FLESH_PINK = rgba(74, 44, 54, 255);
pub const FLESH_PINK_DK = rgba(48, 28, 36, 255);
pub const RUST = rgba(58, 38, 24, 255);
pub const ASH = rgba(78, 74, 70, 255);
pub const ASH_LT = rgba(96, 92, 86, 255);
pub const ASH_DK = rgba(46, 43, 40, 255);
pub const WATER_DEEP = rgba(13, 19, 21, 255);
pub const WATER_MID = rgba(18, 25, 26, 255);
pub const WATER_SHALLOW = rgba(30, 35, 31, 255);
pub const WATER_MUD = rgba(40, 35, 25, 255);
pub const OIL_SHALLOW = rgba(20, 17, 14, 255);
pub const OIL_MID = rgba(11, 10, 9, 255);
pub const OIL_DEEP = rgba(5, 5, 6, 255);
// THE STEW IS NOT A LIGHT. Sampled through the chain (albedo x1.72 -> gamma 1/2.2) the old rim came back 255/205/172 — past the clip on red — over a fungal bloom that reads 121/87/98. Solved back against that bank: the rim lands at 145/95/84 and the deep well at 87/43/59.
pub const FUNGAL_SHALLOW = rgba(43, 17, 13, 255);
pub const FUNGAL_MID = rgba(26, 8, 9, 255);
pub const FUNGAL_DEEP = rgba(14, 4, 6, 255);
pub const LAVA_SHALLOW = rgba(150, 40, 18, 255);
pub const LAVA_MID = rgba(238, 122, 34, 255);
pub const LAVA_DEEP = rgba(255, 232, 148, 255);

/// `y0` is the collider's FOOT and is 0 for every wall: raise it and the capsule becomes a LINTEL (`collision.Solid.y0`) — the stone over a doorway, open to a body on the ground and solid to one on a deck.
/// `flat` gives the capsule square ends (`collision.Solid.flat`): a wall or a block is its bounding rectangle, not a sausage.
pub const Part = struct { ax: f32 = 0, az: f32 = 0, bx: f32 = 0, bz: f32 = 0, r: f32, h: f32, y0: f32 = 0, flat: bool = false };

pub const Deck = struct { x: f32 = 0, z: f32 = 0, r: f32, y: f32, hole: bool = false };

/// A STACKED kind that is walked rather than climbed: each section also advances `run` along local −Z and its walkable surface is `treads` level steps, `halfW` wide. Read with `Info.stack` (the section's rise).
pub const Flight = struct { run: f32, halfW: f32, treads: u32 };

/// A volume a prop blocks the VIEW with (`props.Info.occl`). Here beside `Part` rather than in `props.zig` because a family file that builds its own colliders needs to build its own occluders too, and `props.zig` imports the families.
pub const Blocker = struct { r: f32, y0: f32 = 0, y1: f32, x: f32 = 0, z: f32 = 0 };

pub const TOWER_R: f32 = 4.70;
pub const TOWER_SIDES: i32 = 28;
pub const TOWER_DOOR: i32 = 3;
pub const TOWER_PLINTH: f32 = 0.44;
pub const TOWER_COURSE_H: f32 = 0.76;
pub const TOWER_COURSES: i32 = 30;
fn courseTop(n: i32) f32 {
    return TOWER_PLINTH + @as(f32, @floatFromInt(n)) * TOWER_COURSE_H;
}
pub const TOWER_HEAD: f32 = courseTop(TOWER_COURSES);
pub const TOWER_DOOR_COURSES: i32 = 4;
pub const TOWER_DOOR_HEAD: f32 = courseTop(TOWER_DOOR_COURSES);
pub const TOWER_WALL_R: f32 = 0.62;
pub const HERO_R_HERE: f32 = 0.36;
pub const TOWER_CLEAR: f32 = TOWER_R - TOWER_WALL_R - HERO_R_HERE;
pub const TOWER_WALL_H: f32 = 22.40;
pub const towerRing = blk: {
    var out: [TOWER_SIDES]Part = undefined;
    var n: usize = 0;
    for (0..TOWER_SIDES) |i| {
        const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, TOWER_SIDES);
        const door = towerDoorway(@intCast(i));
        out[n] = .{ .ax = @sin(a) * TOWER_R, .az = -@cos(a) * TOWER_R, .bx = @sin(a) * TOWER_R, .bz = -@cos(a) * TOWER_R, .r = TOWER_WALL_R, .h = TOWER_WALL_H, .y0 = if (door) TOWER_DOOR_HEAD else 0 };
        n += 1;
    }
    std.debug.assert(n == out.len);
    break :blk out;
};

pub fn towerDoorway(i: i32) bool {
    const half = @divTrunc(TOWER_DOOR, 2);
    return @mod(i + half, TOWER_SIDES) < TOWER_DOOR;
}

comptime {
    std.debug.assert(TOWER_DOOR_COURSES < TOWER_COURSES);
    std.debug.assert(TOWER_DOOR_HEAD < TOWER_HEAD);
}



pub const Course = struct {
    thick: f32,
    height: f32,
    y0: f32 = 0,
    courses: i32 = 9,
    blockW: f32 = 0.72,
    crumbleTop: f32 = 0.45,
    crumble: f32 = 0.04,
    gapLo: f32 = 9,
    gapHi: f32 = 9,
    sillY: f32 = 0,
    headY: f32 = 0,
    core: f32 = 0.80,
    /// The stone this run is cut from; null is the grey `STONE` set every ruin is built of. `burn` is the core, because a wall's guts are the face's own stone unweathered.
    tone: ?Tone = null,
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
            const yc = spec.y0 + @as(f32, @floatFromInt(c)) * ch + ch * 0.5;
            const open = yc > spec.sillY and yc < spec.headY;
            const lo: f32 = if (open) spec.gapLo else runLen * 0.5;
            const hi: f32 = if (open) spec.gapHi else runLen * 0.5;
            const spans = [2][2]f32{ .{ -runLen * 0.5, @min(lo, runLen * 0.5) }, .{ @max(hi, -runLen * 0.5), runLen * 0.5 } };
            for (spans, 0..) |sp, si| {
                if (si == 1 and !open) break;
                const w = sp[1] - sp[0];
                if (w <= 0.02) continue;
                const mid = (sp[0] + sp[1]) * 0.5;
                bb.addBox(
                    v3(ax + ux * (runLen * 0.5 + mid), yc, az + uz * (runLen * 0.5 + mid)),
                    v3(ux * w * 0.5, 0, uz * w * 0.5),
                    v3(0, ch * 0.56, 0),
                    v3(-uz * spec.thick * spec.core, 0, ux * spec.thick * spec.core),
                    if (spec.tone) |tn| tn.burn else MORTAR,
                );
            }
        }
    }
    var c: i32 = 0;
    while (c < spec.courses) : (c += 1) {
        const yc = spec.y0 + @as(f32, @floatFromInt(c)) * ch + ch * 0.5;
        const crumble: f32 = if (c >= spec.courses - 2) spec.crumbleTop else spec.crumble;
        const nb: i32 = @intFromFloat(@max(runLen / spec.blockW, 2.0));
        var i: i32 = 0;
        while (i < nb) : (i += 1) {
            const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(nb));
            const s = (t - 0.5) * runLen;
            if (s > spec.gapLo and s < spec.gapHi and yc > spec.sillY and yc < spec.headY) continue;
            if (r.float() < crumble) continue;
            const bw = (runLen / @as(f32, @floatFromInt(nb))) * r.range(1.20, 1.50);
            const col = if (spec.tone) |tn|
                (if (r.float() < 0.15) tn.stoneLt else if (r.float() < 0.32) tn.stoneDk else tn.stone)
            else if (r.float() < 0.15) STONE_LT else if (r.float() < 0.32) STONE_DK else STONE;
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

pub fn courseStack(bb: *Builder, r: *mathx.Rng, cx: f32, y0: f32, cz: f32, w: f32, d: f32, ch: f32, n: i32, taper: f32, tone: ?Tone) f32 {
    bb.setMat(.stone);
    const total = ch * @as(f32, @floatFromInt(n));
    bb.addCube(v3(cx, y0 + total * 0.5, cz), v3(w * (1.0 - taper * 0.5) * 0.94, total, d * (1.0 - taper * 0.5) * 0.94), if (tone) |t| t.burn else MORTAR);
    var y = y0;
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
        const sw = w * (1.0 - taper * t) * r.range(0.99, 1.014);
        const sd = d * (1.0 - taper * t) * r.range(0.99, 1.014);
        const h = ch * r.range(1.0, 1.08);
        bb.addBox(
            v3(cx + r.signed() * 0.026, y + h * 0.45, cz + r.signed() * 0.026),
            v3(sw * 0.5, r.signed() * 0.008, r.signed() * 0.007),
            v3(0, h * 0.5, 0),
            v3(r.signed() * 0.007, 0, sd * 0.5),
            if (tone) |tn|
                (if (r.float() < (if (@mod(i, 2) == 0) @as(f32, 0.5) else 0.24)) tn.stoneDk else if (r.float() < 0.16) tn.stoneLt else tn.stone)
            else if (r.float() < (if (@mod(i, 2) == 0) @as(f32, 0.5) else 0.24)) STONE_DK else if (r.float() < 0.16) STONE_LT else STONE,
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

/// **THE PALETTE A GILDED FAMILY IS DRAWN IN, AND THE ONLY THING THAT SEPARATES TWO OF THEM.** The muqarnas,
/// the band, the ring and the star below are ONE implementation each; the Gilded Ruins pass `propgold.GILT`
/// and the Sun Palace `proppalace.SUN`, and nothing else about the ornament differs.
pub const Tone = struct {
    stone: rl.Color,
    stoneLt: rl.Color,
    stoneDk: rl.Color,
    /// The same stone with the fire's or the sun's mark on it, not a third stone.
    burn: rl.Color,
    gold: rl.Color,
    goldLt: rl.Color,
    goldDk: rl.Color,

    pub fn stoneOf(t: Tone, r: *mathx.Rng) rl.Color {
        const f = r.float();
        if (f < 0.16) return t.stoneLt;
        if (f < 0.34) return t.stoneDk;
        if (f < 0.42) return t.burn;
        return t.stone;
    }

    pub fn goldOf(t: Tone, r: *mathx.Rng) rl.Color {
        const f = r.float();
        if (f < 0.30) return t.goldLt;
        if (f < 0.52) return t.goldDk;
        return t.gold;
    }
};

pub const MUQ_TIERS: i32 = 4;
// Share of the whole rise each tier hangs out past the one below. Real ones project under half.
pub const MUQ_STEP: f32 = 0.15;
comptime {
    // `muqarnasInto` widens each tier over `MUQ_TIERS - 1`; at one tier that is a divide by zero.
    std.debug.assert(MUQ_TIERS > 1);
}

/// `addDome` spends `sides * 3` triangles on each niche: at 8 that is 2,688 on one column, at 6 it is 2,016, and the difference is invisible on a hollow 0.34 m across at the 320 m the kind is drawn to.
const NICHE_SIDES: i32 = 6;

pub fn muqarnasInto(bb: *Builder, r: *mathx.Rng, c: rl.Vector3, face: rl.Vector3, w: f32, up: f32, gild: f32, t: Tone) void {
    const th = up / @as(f32, @floatFromInt(MUQ_TIERS));
    const f = mathx.normV(v3(face.x, 0, face.z));
    const s = v3(-f.z, 0, f.x);
    var tier: i32 = 0;
    while (tier < MUQ_TIERS) : (tier += 1) {
        const ft = @as(f32, @floatFromInt(tier));
        const y = c.y + th * (ft + 0.5);
        const grow = 0.58 + 0.42 * ft / @as(f32, @floatFromInt(MUQ_TIERS - 1));
        const half = w * 0.5 * grow;
        const out = MUQ_STEP * up * ft;
        const depth = th * 1.05;
        bb.setMat(.stone);
        bb.addBox(
            v3(c.x + f.x * (out + depth * 0.5), y + th * 0.30, c.z + f.z * (out + depth * 0.5)),
            v3(s.x * half, r.signed() * 0.004, s.z * half),
            v3(0, th * 0.20, 0),
            v3(f.x * depth * 0.5, 0, f.z * depth * 0.5),
            if (r.float() < 0.22) t.stoneLt else t.stone,
        );
        const cells: i32 = 2 + tier;
        var i: i32 = 0;
        while (i < cells) : (i += 1) {
            const u = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(cells));
            const off = (u - 0.5) * half * 2.0;
            const pitch = half * 2.0 / @as(f32, @floatFromInt(cells));
            const cx = c.x + s.x * (off + pitch * 0.5) + f.x * (out + depth * 0.42);
            const cz = c.z + s.z * (off + pitch * 0.5) + f.z * (out + depth * 0.42);
            if (i + 1 < cells) {
                bb.addBox(
                    v3(cx, y - th * 0.12, cz),
                    v3(s.x * pitch * 0.16, 0, s.z * pitch * 0.16),
                    v3(0, th * 0.36, 0),
                    v3(f.x * depth * 0.40, 0, f.z * depth * 0.40),
                    t.stoneOf(r),
                );
            }
            const nx = c.x + s.x * off + f.x * (out + depth * 0.12);
            const nz = c.z + s.z * off + f.z * (out + depth * 0.12);
            const nr = @min(pitch * 0.40, th * 0.42);
            const leaf = r.float() < gild;
            bb.setMat(if (leaf) .gilt else .stone);
            bb.addDome(
                v3(nx, y - th * 0.06, nz),
                f,
                nr,
                NICHE_SIDES,
                if (leaf) t.goldOf(r) else t.burn,
            );
        }
    }
}

/// A COURSE OF IT IS ALWAYS GONE — the chance a plate has been prised off, one number for the band and the ring.
const GILT_GONE: f32 = 0.22;

/// A gilded frieze round a SQUARE mass; `halfX`/`halfZ` are the mass's own half-extents.
pub fn giltBandInto(bb: *Builder, r: *mathx.Rng, cx: f32, y: f32, cz: f32, halfX: f32, halfZ: f32, h: f32, t: Tone) void {
    bb.setMat(.gilt);
    for ([_][2]f32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |s| {
        if (r.float() < GILT_GONE) continue;
        const along = v3(s[1] * halfX * 0.92, 0, s[0] * halfZ * 0.92);
        bb.addBox(
            v3(cx + s[0] * halfX, y + r.signed() * 0.01, cz + s[1] * halfZ),
            along,
            v3(0, h * 0.5, 0),
            v3(s[0] * 0.022, 0, s[1] * 0.022),
            t.goldOf(r),
        );
    }
}

/// …and the same frieze round a ROUND or POLYGONAL one. Plates laid tangentially with gaps: a four-plate square band on a 0.40 m column hangs its corners 0.16 m out in the air.
pub fn giltRingInto(bb: *Builder, r: *mathx.Rng, cx: f32, y: f32, cz: f32, radius: f32, h: f32, sides: i32, t: Tone) void {
    bb.setMat(.gilt);
    const n: f32 = @floatFromInt(sides);
    var i: i32 = 0;
    while (i < sides) : (i += 1) {
        if (r.float() < GILT_GONE) continue;
        const a = std.math.tau * (@as(f32, @floatFromInt(i)) + 0.5) / n;
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        const half = std.math.tau * radius / n * 0.46;
        bb.addBox(
            v3(cx + ca * radius, y + r.signed() * 0.01, cz + sa * radius),
            v3(-sa * half, 0, ca * half),
            v3(0, h * 0.5, 0),
            v3(ca * 0.026, 0, sa * 0.026),
            t.goldOf(r),
        );
    }
}

/// The eight-point star (khatim) — two squares at 45 degrees. Laid FLAT as a plan for basins and paving.
pub fn starInto(bb: *Builder, r: *mathx.Rng, c: rl.Vector3, out: f32, h: f32, col: rl.Color, t: Tone) void {
    for ([_]f32{ 0, 45.0 }) |deg| {
        const a = mathx.radians(deg);
        const ca = mathx.cosf(a);
        const sa = mathx.sinf(a);
        bb.addBox(
            c,
            v3(ca * out, 0, sa * out),
            v3(0, h * 0.5, 0),
            v3(-sa * out, 0, ca * out),
            if (r.float() < 0.3) t.stoneDk else col,
        );
    }
}

pub const WEAVE = rgba(88, 80, 62, 255);
pub const WEAVE_DK = rgba(28, 32, 44, 255);
pub const MADDER = rgba(66, 34, 28, 255);
pub const MADDER_LT = rgba(86, 48, 38, 255);

pub const HEARTH_FLAMES = [3]f32{ 2.20, 1.45, 1.05 };


/// Drab, because a bedroll is not a banner. Solved (`albedo = screen^2.2 / 1.72`): mat 157 -> 52, wool 141 -> 40, sack 131 -> 34. THE ONE WARM STRIPE IS THE WHOLE ACCENT, authored in the hero's crimson (`CLOTH`, 76,20,12).
pub const MAT = rgba(52, 46, 32, 255);
pub const MAT_DK = rgba(34, 30, 21, 255);
pub const WOOL = rgba(40, 38, 34, 255);
pub const WOOL_LT = rgba(56, 53, 47, 255);
pub const WOOL_STRIPE = rgba(86, 44, 34, 255);
pub const KIT = rgba(34, 28, 21, 255);
pub const KIT_LT = rgba(48, 40, 30, 255);

pub fn bedrollInto(b: *Builder, rng: *mathx.Rng, cx: f32, cz: f32, yaw: f32) void {
    const ux = mathx.cosf(yaw);
    const uz = mathx.sinf(yaw);
    const vx = -uz;
    const vz = ux;
    const HALF: f32 = 0.88;
    const WIDE: f32 = 0.34;

    b.setMat(.cloth);
    b.addBox(
        v3(cx, 0.048, cz),
        v3(ux * HALF, rng.signed() * 0.010, uz * HALF),
        v3(0, 0.048, 0),
        v3(vx * WIDE, rng.signed() * 0.008, vz * WIDE),
        MAT_DK,
    );
    for ([_]f32{ -1.0, 1.0 }) |side| {
        var i: i32 = 0;
        while (i < 5) : (i += 1) {
            const t = (@as(f32, @floatFromInt(i)) / 4.0 - 0.5) * 1.82;
            const bulge = rng.range(0.98, 1.16);
            b.addCapsule(
                v3(cx + ux * HALF * t + vx * WIDE * side * bulge, 0.052, cz + uz * HALF * t + vz * WIDE * side * bulge),
                v3(cx + ux * HALF * (t + 0.22) + vx * WIDE * side * bulge * 0.94, 0.046, cz + uz * HALF * (t + 0.22) + vz * WIDE * side * bulge * 0.94),
                rng.range(0.040, 0.062),
                rng.range(0.034, 0.052),
                5,
                if (rng.float() < 0.3) MAT else MAT_DK,
            );
        }
    }

    b.addBox(
        v3(cx - ux * HALF * 0.16, 0.140, cz - uz * HALF * 0.16),
        v3(ux * HALF * 0.78, rng.signed() * 0.012, uz * HALF * 0.78),
        v3(0, 0.046, 0),
        v3(vx * WIDE * 0.90, rng.signed() * 0.010, vz * WIDE * 0.90),
        WOOL,
    );
    for ([_]f32{ -1.0, 1.0 }) |side| {
        var i: i32 = 0;
        while (i < 4) : (i += 1) {
            const t = (@as(f32, @floatFromInt(i)) / 3.0 - 0.62) * 1.34;
            b.addCapsule(
                v3(cx + ux * HALF * t + vx * WIDE * side * 0.88, 0.132, cz + uz * HALF * t + vz * WIDE * side * 0.88),
                v3(cx + ux * HALF * t + vx * WIDE * side * 1.00, 0.096, cz + uz * HALF * t + vz * WIDE * side * 1.00),
                rng.range(0.038, 0.058),
                rng.range(0.030, 0.046),
                5,
                if (rng.float() < 0.35) WOOL_LT else WOOL,
            );
        }
    }
    for ([_]f32{ -0.56, -0.18 }) |t| {
        b.addBox(
            v3(cx + ux * HALF * t, 0.148, cz + uz * HALF * t),
            v3(ux * 0.050, 0, uz * 0.050),
            v3(0, 0.042, 0),
            v3(vx * WIDE * 0.91, 0, vz * WIDE * 0.91),
            WOOL_STRIPE,
        );
    }
    b.addCylinder(
        v3(cx + ux * HALF * 0.60 + vx * WIDE * 0.86, 0.188, cz + uz * HALF * 0.60 + vz * WIDE * 0.86),
        v3(cx + ux * HALF * 0.64 - vx * WIDE * 0.86, 0.182, cz + uz * HALF * 0.64 - vz * WIDE * 0.86),
        0.072,
        0.066,
        8,
        WOOL_LT,
    );

    b.addBlob(v3(cx + ux * HALF * 0.80 - vx * 0.05, 0.150, cz + uz * HALF * 0.80 - vz * 0.05), v3(0.155, 0.070, 0.140), 4, 9, WOOL_LT);
    b.addBlob(v3(cx + ux * HALF * 0.86 + vx * 0.08, 0.170, cz + uz * HALF * 0.86 + vz * 0.08), v3(0.105, 0.055, 0.095), 3, 8, WOOL);

    const rfx = cx - ux * (HALF + 0.06);
    const rfz = cz - uz * (HALF + 0.06);
    b.addCylinder(
        v3(rfx + vx * WIDE * 0.86, 0.128, rfz + vz * WIDE * 0.86),
        v3(rfx - vx * WIDE * 0.86, 0.122, rfz - vz * WIDE * 0.86),
        0.110,
        0.104,
        9,
        MAT,
    );
    b.addBlob(v3(rfx + vx * WIDE * 0.88, 0.128, rfz + vz * WIDE * 0.88), v3(0.028, 0.104, 0.104), 3, 9, MAT_DK);
    b.addBlob(v3(rfx + vx * WIDE * 0.92, 0.128, rfz + vz * WIDE * 0.92), v3(0.020, 0.046, 0.046), 3, 7, WOOL_STRIPE);
    b.addCylinder(
        v3(rfx + vx * WIDE * 0.16, 0.128, rfz + vz * WIDE * 0.16),
        v3(rfx + vx * WIDE * 0.02, 0.126, rfz + vz * WIDE * 0.02),
        0.115,
        0.115,
        9,
        KIT,
    );

    b.setMat(.leather);
    const hx = cx + ux * (HALF + 0.24) + vx * 0.30;
    const hz = cz + uz * (HALF + 0.24) + vz * 0.30;
    b.addBlob(v3(hx, 0.135, hz), v3(0.185, 0.130, 0.160), 4, 9, KIT);
    b.addBlob(v3(hx + ux * 0.09, 0.185, hz + uz * 0.09), v3(0.110, 0.080, 0.100), 4, 8, KIT_LT);
    b.addCylinder(
        v3(hx + vx * 0.185, 0.140, hz + vz * 0.185),
        v3(hx - vx * 0.185, 0.136, hz - vz * 0.185),
        0.028,
        0.026,
        6,
        MAT_DK,
    );
    for ([_]f32{ -1.0, 1.0 }) |side| {
        const bx = cx + ux * (HALF + 0.10) - vx * (0.44 + side * 0.11);
        const bz = cz + uz * (HALF + 0.10) - vz * (0.44 + side * 0.11);
        b.addCapsule(
            v3(bx, 0.052, bz),
            v3(bx - ux * 0.17, 0.048, bz - uz * 0.17),
            0.058,
            0.047,
            6,
            KIT,
        );
        b.addBlob(v3(bx - ux * 0.20, 0.046, bz - uz * 0.20), v3(0.054, 0.042, 0.070), 3, 7, KIT_LT);
    }
    b.setMat(.plain);
}

pub fn smokeInto(b: *Builder, rng: *mathx.Rng, src: f32, s: f32) void {
    const PUFFS = 14;
    b.setMat(.smoke);
    var i: i32 = 0;
    while (i < PUFFS) : (i += 1) {
        const phase = (@as(f32, @floatFromInt(i)) + rng.range(0, 0.55)) / @as(f32, @floatFromInt(PUFFS));
        b.setAnimY(gfx.smokeAnim(src, phase));
        const r = rng.range(0.135, 0.235) * s;
        b.addBlob(
            v3(rng.signed() * 0.10 * s, src + rng.signed() * 0.06, rng.signed() * 0.10 * s),
            v3(r, r * rng.range(0.72, 0.98), r * rng.range(0.85, 1.20)),
            3,
            7,
            if (phase < 0.3) SMOKE_HOT else if (phase < 0.65) SMOKE_MID else SMOKE_COLD,
        );
    }
    b.setMat(.ember);
    var e: i32 = 0;
    while (e < 26) : (e += 1) {
        const phase = (@as(f32, @floatFromInt(e)) + rng.range(0, 0.9)) / 26.0;
        b.setAnimY(gfx.smokeAnim(src, phase));
        const a = rng.angle();
        const dd = rng.range(0.04, 0.30) * s;
        const sz = rng.range(0.018, 0.038) * s;
        b.addBlob(
            v3(mathx.cosf(a) * dd, src - rng.range(0.18, 0.34), mathx.sinf(a) * dd),
            v3(sz, sz, sz),
            2,
            5,
            if (rng.float() < 0.75) EMBER else WISP,
        );
    }
    b.setAnimY(0);
    b.setMat(.plain);
}

pub fn flameInto(b: *Builder, rng: *mathx.Rng, cx: f32, cy: f32, cz: f32, s: f32) void {
    b.setMat(.flame);
    b.setAnimY(cy);
    b.addBlob(v3(cx, cy + 0.015 * s, cz), v3(0.175 * s, 0.045 * s, 0.175 * s), 3, 9, COAL);
    b.addBlob(v3(cx, cy + 0.055 * s, cz), v3(0.078 * s, 0.048 * s, 0.078 * s), 3, 8, FLAME_CORE);
    var t: i32 = 0;
    while (t < 6) : (t += 1) {
        const a = rng.angle();
        const off = rng.range(0.02, 0.115) * s;
        const h = rng.range(0.17, 0.44) * s;
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
    b.setAnimY(0);
}
/// **WABI-SABI GOES BETWEEN THE INSTANCES, NOT ALONG ONE** (the house rule) — two tones alternated segment by segment band a shaft like a barber's pole; the same two as a slow lerp foot to tip read as weathering. `t` is 0 at the foot and 1 at the tip.
pub fn weathered(foot: rl.Color, tip: rl.Color, t: f32) rl.Color {
    return mathx.lerpColor(foot, tip, mathx.smoothstep(0.0, 1.0, t));
}

pub fn seam(base: rl.Color, dark: rl.Color, i: i32, every: i32) rl.Color {
    return if (@mod(i, every) == every - 1) dark else base;
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

const GUITAR_BODY = [_][3]f32{
    .{ 0.000, 0.023, 0.030 },
    .{ 0.024, 0.104, 0.046 },
    .{ 0.058, 0.158, 0.053 },
    .{ 0.104, 0.190, 0.056 },
    .{ 0.152, 0.198, 0.056 },
    .{ 0.208, 0.191, 0.055 },
    .{ 0.258, 0.164, 0.053 },
    .{ 0.300, 0.135, 0.051 },
    .{ 0.344, 0.145, 0.049 },
    .{ 0.394, 0.165, 0.047 },
    .{ 0.444, 0.166, 0.045 },
    .{ 0.488, 0.138, 0.043 },
    .{ 0.520, 0.070, 0.042 },
};

pub fn guitarRockInto(b: *Builder, rng: *mathx.Rng, cx: f32, cz: f32) void {
    b.setMat(.stone);
    b.addBlob(v3(cx, 0.22, cz), v3(0.52, 0.235, 0.46), 4, 9, if (rng.float() < 0.4) STONE_MOSS else STONE_DK);
    b.addBlob(v3(cx + rng.signed() * 0.16, 0.30, cz + rng.signed() * 0.16), v3(0.34, 0.115, 0.31), 3, 8, ROCK_DEEP);
    lichenInto(b, rng, v3(cx + rng.signed() * 0.2, 0.40, cz + rng.signed() * 0.2), v3(0.16, 0.015, 0.15), 3);
}

pub fn guitarLeaningInto(b: *Builder, cx: f32, cz: f32, yaw: f32, scale: f32) void {
    const LEAN: f32 = 0.50;
    const FOOT: f32 = 0.70;
    const cy = mathx.cosf(yaw);
    const sy = mathx.sinf(yaw);
    const cl = mathx.cosf(LEAN);
    const sl = mathx.sinf(LEAN);
    guitarInto(b, .{
        .o = v3(cx + cy * FOOT, 0.020, cz + sy * FOOT),
        .w = v3(sy, 0, -cy),
        .a = v3(-cy * sl, cl, -sy * sl),
        .n = v3(cy * cl, sl, sy * cl),
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
    b.addBox(fr.at(0, 0.868, 0.0555), fr.axis(0.028, 0, 0), fr.axis(0, 0.004, 0), fr.axis(0, 0, 0.004), BONE);
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


pub const CLOTH_SIDES_MAX = 40;

/// ONE FOLDED SURFACE, not a stack of skirts. `rings` are `[x, y, z, radiusX, radiusZ]` in STATURE-RELATIVE units with the BOTTOM ROW FIRST; every row shares one set of angular samples, so a fold runs the whole drop instead of stopping at each seam.
pub const Cloth = struct {
    sides: usize = 24,
    /// Radial wobble as a fraction of the ring radius — the vertical folds. A few percent; more and the surface reads as a gear.
    fold: f32 = 0.035,
    ragged: bool = false,
    hemLo: f32 = -0.024,
    hemHi: f32 = 0.016,
    scale: f32 = 1.0,
    mix: f32 = 0.4,
};

pub fn clothInto(b: *Builder, rings: []const [5]f32, seed: u64, dark: rl.Color, light: rl.Color, o: Cloth) void {
    if (rings.len < 2) return; // `rings.len - 1` underflows usize, and one row is not a surface
    const sides = @min(o.sides, CLOTH_SIDES_MAX);
    var rng = mathx.Rng.init(seed);
    var fold: [CLOTH_SIDES_MAX]f32 = undefined;
    var hem: [CLOTH_SIDES_MAX]f32 = undefined;
    var col: [CLOTH_SIDES_MAX]rl.Color = undefined;
    for (0..sides) |i| {
        fold[i] = 1 + rng.signed() * o.fold;
        hem[i] = if (o.ragged) rng.range(o.hemLo, o.hemHi) else 0;
        col[i] = mathx.lerpColor(dark, light, rng.range(0, o.mix));
    }
    const fs: f32 = @floatFromInt(sides);
    for (rings[0 .. rings.len - 1], rings[1..], 0..) |lo, hi, row| {
        for (0..sides) |i| {
            const j = (i + 1) % sides;
            var points: [4]rl.Vector3 = undefined;
            for ([_][2]usize{ .{ i, 0 }, .{ i, 1 }, .{ j, 1 }, .{ j, 0 } }, 0..) |at, n| {
                const ring = if (at[1] == 0) lo else hi;
                const angle = std.math.tau * @as(f32, @floatFromInt(at[0])) / fs;
                const y = ring[1] + (if (row == 0 and at[1] == 0) hem[at[0]] else 0);
                points[n] = v3((ring[0] + ring[3] * mathx.cosf(angle) * fold[at[0]]) * o.scale, y * o.scale, (ring[2] + ring[4] * mathx.sinf(angle) * fold[at[0]]) * o.scale);
            }
            const normal = mathx.normV(mathx.crossV(mathx.subV(points[1], points[0]), mathx.subV(points[2], points[0])));
            b.quad(points[0], points[1], points[2], points[3], normal, col[i]);
            b.quad(points[3], points[2], points[1], points[0], mathx.scaleV(normal, -1), col[i]);
        }
    }
}
