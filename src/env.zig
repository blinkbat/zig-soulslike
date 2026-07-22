const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");

const v3 = mathx.v3;
const rgba = mathx.rgba;
const Builder = gfx.Builder;

// The world: a golden-grass plain crossed by a worn path (the terrain shader carves it
// along x ~ 0), dressed as a fallen kingdom — a colonnade avenue with a gate arch over
// the path, ruined walls, dead trees, graves, swords left in the earth, a grace-like
// ember brazier (the shader's emissive vertex-alpha channel), and colossal hazed ruin
// silhouettes on the horizon for depth. All static — drawn with drawModelEx (single Y
// rotation) and shadow-swapped like zig-rts.

pub const HALF: f32 = 60.0; // playable bounds span [-HALF, +HALF] on X and Z
// The ground QUAD extends far past the bounds so the terrain runs all the way into full
// distance haze — no visible plane edge / sky band below the horizon.
const GROUND_HALF: f32 = 240.0;

// Stone palette (pre-gamma dark — the scene shader gammas output). Warm grey so the
// golden sun reads on it; moss and soot for age.
const STONE = rgba(80, 76, 68, 255);
const STONE_LT = rgba(94, 90, 80, 255);
const STONE_DK = rgba(54, 50, 44, 255);
const STONE_MOSS = rgba(52, 58, 40, 255);
const BARK = rgba(36, 29, 22, 255);
const BARK_DK = rgba(26, 21, 17, 255);
const IRON = rgba(30, 28, 26, 255);
const STEEL = rgba(100, 106, 116, 255);
const BRASS = rgba(122, 92, 40, 255);
// Emissive (vertex alpha < 255 = self-lit): the grace ember and its wisp.
const EMBER = rgba(240, 162, 58, 40);
const WISP = rgba(250, 196, 110, 120);

// Prop kinds — indices into Env.models.
const K_PILLAR = 0;
const K_BROKEN = 1;
const K_BLOCK = 2;
const K_ARCH = 3;
const K_WALL = 4;
const K_TREE = 5;
const K_GRAVES = 6;
const K_SWORD = 7;
const K_GRACE = 8;
const K_TOWER = 9;
const K_GATE = 10;
const K_RUBBLE = 11;
const K_BANNER = 12;
const K_STATUE = 13;
const K_TUFT = 14; // one golden grass clump
const K_PATCH = 15; // a wide swathe of grass clumps
const K_SHRUB = 16; // low dark scrub bush
const K_FLOWERS = 17; // pale erdleaf-like blooms in grass
const K_REEDS = 18; // tall dry sedge with seed heads
const K_GLOW = 19; // faintly glowing blooms (grace-side accents)
const NK = 20;
const CLOTH = rgba(76, 20, 12, 255); // faded war-banner crimson (matches the hero's cape)

// Plant palette (pre-gamma dark) — Limgrave gold over scrub green.
const GRASS_GOLD = rgba(96, 76, 34, 255);
const GRASS_DRY = rgba(78, 64, 30, 255);
const GRASS_GRN = rgba(50, 56, 28, 255);
const SCRUB = rgba(38, 46, 26, 255);
const SCRUB_DK = rgba(28, 34, 20, 255);
const STEM = rgba(44, 54, 28, 255);
const PETAL = rgba(210, 196, 152, 255);
const SEED = rgba(118, 94, 46, 255);
const PETAL_GLOW = rgba(242, 206, 118, 200); // slight emissive — kin to the grace ember

// Hand-placed composition. The hero's runway (x = 0, z 26 -> -40, used by --shot and the
// live start) stays clear; the arch spans it so you run THROUGH the ruin, and the distant
// gate sits on its axis so the avenue frames it. Horizon giants live near the world edge
// where the haze dissolves them into silhouettes.
const P = struct { x: f32, z: f32, yaw: f32, s: f32, kind: u8 };
const layout = [_]P{
    // colonnade avenue flanking the path
    .{ .x = -6, .z = 14, .yaw = 8, .s = 0.9, .kind = K_BROKEN },
    .{ .x = 6, .z = 12, .yaw = 0, .s = 1.0, .kind = K_PILLAR },
    .{ .x = -6, .z = -6, .yaw = 0, .s = 1.0, .kind = K_PILLAR },
    .{ .x = 6, .z = -6, .yaw = 0, .s = 1.1, .kind = K_PILLAR },
    .{ .x = -6, .z = -16, .yaw = 0, .s = 1.0, .kind = K_BROKEN },
    .{ .x = 6, .z = -16, .yaw = 12, .s = 1.0, .kind = K_PILLAR },
    .{ .x = -6, .z = -26, .yaw = 0, .s = 0.95, .kind = K_PILLAR },
    .{ .x = 6, .z = -26, .yaw = 0, .s = 1.05, .kind = K_BROKEN },
    .{ .x = -6, .z = -36, .yaw = -6, .s = 1.05, .kind = K_PILLAR },
    .{ .x = 6, .z = -36, .yaw = 20, .s = 0.95, .kind = K_BROKEN },
    // the gate arch over the path
    .{ .x = 0, .z = -31, .yaw = 0, .s = 1.0, .kind = K_ARCH },
    // the grace ember, just off the path by the start
    .{ .x = 3.0, .z = 6.5, .yaw = 0, .s = 1.0, .kind = K_GRACE },
    // ruined walls
    .{ .x = -14, .z = -14, .yaw = 78, .s = 1.1, .kind = K_WALL },
    .{ .x = 15, .z = -40, .yaw = -12, .s = 1.2, .kind = K_WALL },
    .{ .x = -24, .z = -28, .yaw = 100, .s = 0.9, .kind = K_WALL },
    // dead trees
    .{ .x = -12, .z = -2, .yaw = 0, .s = 1.1, .kind = K_TREE },
    .{ .x = 16, .z = -31, .yaw = 140, .s = 1.3, .kind = K_TREE },
    .{ .x = -20, .z = -38, .yaw = 70, .s = 0.9, .kind = K_TREE },
    .{ .x = 24, .z = 6, .yaw = 200, .s = 1.0, .kind = K_TREE },
    // graveyard cluster + a stray marker
    .{ .x = -11, .z = -29, .yaw = 15, .s = 1.0, .kind = K_GRAVES },
    .{ .x = -14, .z = -33, .yaw = -40, .s = 0.9, .kind = K_GRAVES },
    .{ .x = 13, .z = -26, .yaw = 60, .s = 0.8, .kind = K_GRAVES },
    // swords left standing in the earth
    .{ .x = -2.8, .z = -21, .yaw = 30, .s = 1.0, .kind = K_SWORD },
    .{ .x = 10, .z = -8, .yaw = -70, .s = 0.9, .kind = K_SWORD },
    .{ .x = -12.5, .z = -31, .yaw = 120, .s = 1.1, .kind = K_SWORD },
    // ruin blocks
    .{ .x = 15, .z = -3, .yaw = -25, .s = 1.3, .kind = K_BLOCK },
    .{ .x = 13, .z = -22, .yaw = 70, .s = 1.0, .kind = K_BLOCK },
    .{ .x = -9, .z = -44, .yaw = 30, .s = 1.0, .kind = K_BLOCK },
    .{ .x = 20, .z = -18, .yaw = 55, .s = 1.0, .kind = K_BLOCK },
    .{ .x = -22, .z = -6, .yaw = -35, .s = 0.9, .kind = K_BLOCK },
    // war banners flanking the avenue + a headless sentinel by the grace
    .{ .x = 7.5, .z = -11, .yaw = -18, .s = 1.0, .kind = K_BANNER },
    .{ .x = -7.5, .z = -33, .yaw = 155, .s = 1.1, .kind = K_BANNER },
    .{ .x = -8.5, .z = 7, .yaw = 155, .s = 1.0, .kind = K_STATUE },
    // rubble scatter near the path
    .{ .x = 2.5, .z = -13, .yaw = 45, .s = 1.0, .kind = K_RUBBLE },
    .{ .x = -4, .z = -34, .yaw = 10, .s = 1.0, .kind = K_RUBBLE },
    .{ .x = 8, .z = 2, .yaw = 70, .s = 0.8, .kind = K_RUBBLE },
    .{ .x = -8, .z = -20, .yaw = 0, .s = 1.0, .kind = K_RUBBLE },
    // hand-placed flora accents: glowing blooms hug the grace; flowers among the
    // graves; reeds against the wall feet
    .{ .x = 2.1, .z = 5.5, .yaw = 40, .s = 1.0, .kind = K_GLOW },
    .{ .x = 4.2, .z = 7.6, .yaw = 210, .s = 0.85, .kind = K_GLOW },
    .{ .x = -11.8, .z = -30.6, .yaw = 75, .s = 1.0, .kind = K_FLOWERS },
    .{ .x = 12.4, .z = -27.2, .yaw = 150, .s = 0.9, .kind = K_FLOWERS },
    .{ .x = -13.2, .z = -15.7, .yaw = 25, .s = 1.15, .kind = K_REEDS },
    .{ .x = 14.2, .z = -38.6, .yaw = -60, .s = 1.2, .kind = K_REEDS },
    // denser flowers ringing the graveyard — mourning blooms clustered on the graves
    .{ .x = -9.6, .z = -28.2, .yaw = 20, .s = 0.95, .kind = K_FLOWERS },
    .{ .x = -13.5, .z = -27.8, .yaw = 130, .s = 1.05, .kind = K_FLOWERS },
    .{ .x = -15.4, .z = -31.4, .yaw = 250, .s = 0.9, .kind = K_FLOWERS },
    .{ .x = -12.2, .z = -34.4, .yaw = 300, .s = 1.0, .kind = K_FLOWERS },
    .{ .x = -9.4, .z = -32.6, .yaw = 60, .s = 0.85, .kind = K_FLOWERS },
    .{ .x = 11.0, .z = -24.2, .yaw = 200, .s = 0.9, .kind = K_FLOWERS },
    .{ .x = 14.6, .z = -24.8, .yaw = 20, .s = 0.95, .kind = K_FLOWERS },
    // a reed bed along the world's east side, a hazed band of sedge for depth
    .{ .x = 33.0, .z = -12.0, .yaw = 15, .s = 1.2, .kind = K_REEDS },
    .{ .x = 35.5, .z = -16.5, .yaw = 80, .s = 1.35, .kind = K_REEDS },
    .{ .x = 38.0, .z = -10.0, .yaw = 200, .s = 1.1, .kind = K_REEDS },
    .{ .x = 40.5, .z = -20.0, .yaw = -40, .s = 1.3, .kind = K_REEDS },
    .{ .x = 36.5, .z = -24.0, .yaw = 120, .s = 1.25, .kind = K_REEDS },
    .{ .x = 42.0, .z = -28.0, .yaw = 60, .s = 1.15, .kind = K_REEDS },
    .{ .x = 39.0, .z = -32.0, .yaw = 250, .s = 1.3, .kind = K_REEDS },
    // horizon giants, dissolved by haze
    .{ .x = 2, .z = -56, .yaw = 4, .s = 1.0, .kind = K_GATE },
    .{ .x = -27, .z = -54, .yaw = 10, .s = 1.2, .kind = K_TOWER },
    .{ .x = 31, .z = -50, .yaw = -25, .s = 0.9, .kind = K_TOWER },
    .{ .x = -45, .z = -20, .yaw = 40, .s = 0.8, .kind = K_TOWER },
    .{ .x = 48, .z = -34, .yaw = 15, .s = 1.1, .kind = K_TOWER },
    .{ .x = -38, .z = 40, .yaw = 55, .s = 1.0, .kind = K_TOWER },
    .{ .x = 42, .z = 38, .yaw = -30, .s = 0.85, .kind = K_TOWER },
};

const Prop = struct { kind: u8, pos: rl.Vector3, yaw: f32, scale: f32 };

// Seeded meadow scatter: this many plant props strewn across the plain on top of the
// hand-placed layout, avoiding the worn path (the --shot runway) and every built
// prop's base. Deterministic — same seed, same field, every launch.
const SCATTER = 260;

pub const Env = struct {
    ground: rl.Model,
    models: [NK]rl.Model,
    props: [layout.len + SCATTER]Prop = undefined,

    pub fn init(shader: rl.Shader) Env {
        // Index each mesh by its K_* kind so the array and the kind constants can't drift
        // out of lockstep (a positional list silently desyncs if either side is reordered).
        var models: [NK]rl.Model = undefined;
        models[K_PILLAR] = pillarMesh(shader, false);
        models[K_BROKEN] = pillarMesh(shader, true);
        models[K_BLOCK] = blockMesh(shader);
        models[K_ARCH] = archMesh(shader);
        models[K_WALL] = wallMesh(shader);
        models[K_TREE] = treeMesh(shader);
        models[K_GRAVES] = gravesMesh(shader);
        models[K_SWORD] = swordMesh(shader);
        models[K_GRACE] = graceMesh(shader);
        models[K_TOWER] = towerMesh(shader);
        models[K_GATE] = gateMesh(shader);
        models[K_RUBBLE] = rubbleMesh(shader);
        models[K_BANNER] = bannerMesh(shader);
        models[K_STATUE] = statueMesh(shader);
        models[K_TUFT] = tuftMesh(shader);
        models[K_PATCH] = patchMesh(shader);
        models[K_SHRUB] = shrubMesh(shader);
        models[K_FLOWERS] = flowersMesh(shader);
        models[K_REEDS] = reedsMesh(shader);
        models[K_GLOW] = glowMesh(shader);
        var e = Env{
            .ground = terrain(shader, GROUND_HALF),
            .models = models,
        };
        for (layout, 0..) |p, i| {
            e.props[i] = .{ .kind = p.kind, .pos = mathx.ground(p.x, p.z), .yaw = p.yaw, .scale = p.s };
        }
        scatterPlants(&e);
        return e;
    }

    pub fn setShader(self: *Env, sh: rl.Shader) void {
        self.ground.materials[0].shader = sh;
        for (&self.models) |*m| m.materials[0].shader = sh;
    }

    // Terrain receives shadows but doesn't cast; drawn separately with groundMode on.
    pub fn drawGround(self: *const Env) void {
        rl.drawModel(self.ground, mathx.zero3, 1.0, rl.Color.white);
    }

    // The stone/structure props — shadow casters, drawn in BOTH passes. Flora is skipped
    // here (see drawFlora): thin blades sparkle in the shadow map, and a non-casting plant
    // is free to sway without its shadow desyncing.
    pub fn drawProps(self: *const Env) void {
        for (self.props) |p| {
            if (p.kind >= K_TUFT) continue;
            rl.drawModelEx(self.models[p.kind], p.pos, v3(0, 1, 0), p.yaw, v3(p.scale, p.scale, p.scale), rl.Color.white);
        }
    }

    // The flora — non-casters, drawn only in the lit pass (with the wind term enabled).
    pub fn drawFlora(self: *const Env) void {
        for (self.props) |p| {
            if (p.kind < K_TUFT) continue;
            rl.drawModelEx(self.models[p.kind], p.pos, v3(0, 1, 0), p.yaw, v3(p.scale, p.scale, p.scale), rl.Color.white);
        }
    }
};

// Flat ground plane as one big white quad — the scene shader's terrainAlbedo owns the look.
// Sits a few cm below Y=0 so the hero's soles / prop bases (authored at Y=0) never sit
// exactly coplanar with it (coplanar faces z-fight), with headroom for the run crouch.
const GROUND_Y: f32 = -0.05;
fn terrain(shader: rl.Shader, half: f32) rl.Model {
    var b = Builder.init();
    b.quad(v3(-half, GROUND_Y, -half), v3(-half, GROUND_Y, half), v3(half, GROUND_Y, half), v3(half, GROUND_Y, -half), v3(0, 1, 0), rl.Color.white);
    return b.toModel(shader);
}

// A stone column: stepped plinth, a shaft of stacked drums (radius jogs + alternating
// tint at the joints so the drums read), and (if not broken) a flared capital. Broken
// columns snap partway up a drum, with the fallen drum mossing over beside the plinth.
fn pillarMesh(shader: rl.Shader, broken: bool) rl.Model {
    var b = Builder.init();
    b.addCube(v3(0, 0.18, 0), v3(1.7, 0.36, 1.7), STONE_DK);
    b.addCube(v3(0, 0.46, 0), v3(1.45, 0.24, 1.45), STONE);
    b.addCylinder(v3(0, 0.58, 0), v3(0, 2.0, 0), 0.62, 0.58, 8, STONE);
    if (broken) {
        b.addCylinder(v3(0, 2.0, 0), v3(0, 2.6, 0), 0.585, 0.56, 8, STONE_LT);
        // Jagged snapped top: a short tilted chunk + a drum fallen on the plinth.
        b.addBox(v3(0.12, 2.74, 0.06), v3(0.42, 0.05, 0.10), v3(-0.06, 0.28, 0.05), v3(0.05, 0.02, 0.4), STONE_DK);
        b.addCylinder(v3(1.05, 0.72, 0.35), v3(1.05, 0.72, 1.15), 0.55, 0.52, 8, STONE_MOSS);
    } else {
        b.addCylinder(v3(0, 2.0, 0), v3(0, 3.4, 0), 0.59, 0.545, 8, STONE_LT);
        b.addCylinder(v3(0, 3.4, 0), v3(0, 4.98, 0), 0.555, 0.50, 8, STONE);
        // Capital: a torus-ish flare + abacus slab. The thin slab under the flare closes
        // the cone's open underside (cylinders are capless; from below you'd see through
        // to striped interior backfaces).
        b.addCube(v3(0, 5.00, 0), v3(1.12, 0.06, 1.12), STONE_LT);
        b.addCylinder(v3(0, 4.98, 0), v3(0, 5.28, 0), 0.5, 0.78, 8, STONE_LT);
        b.addCube(v3(0, 5.40, 0), v3(1.5, 0.22, 1.5), STONE_DK);
    }
    return b.toModel(shader);
}

// A broken rectangular ruin block — a squat mossy stone with a chipped upper corner.
fn blockMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.addCube(v3(0, 0.5, 0), v3(2.2, 1.0, 1.6), STONE);
    b.addCube(v3(0, 1.05, 0), v3(2.0, 0.16, 1.4), STONE_MOSS); // mossy cap
    b.addCube(v3(-0.7, 1.35, 0.2), v3(0.7, 0.5, 1.0), STONE_DK); // upstanding chunk
    b.addCube(v3(0.85, 0.28, -0.55), v3(0.6, 0.56, 0.6), STONE_DK); // fallen chip at the base
    return b.toModel(shader);
}

// The gate arch: two square piers spanning the path, twin lintel slabs, and a chipped
// parapet — a threshold you run through, framing the horizon gate beyond.
fn archMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    const px = 2.7; // pier center offset — the path (x ~ 0 +/- 1) passes clean between
    for ([_]f32{ -px, px }) |x| {
        b.addCube(v3(x, 0.22, 0), v3(1.6, 0.44, 1.6), STONE_DK); // base slab
        b.addCube(v3(x, 2.5, 0), v3(1.05, 4.2, 1.05), STONE); // pier
        b.addCube(v3(x, 4.72, 0), v3(1.35, 0.24, 1.35), STONE_LT); // cap
    }
    b.addCube(v3(0, 5.12, 0), v3(7.4, 0.56, 1.2), STONE); // lintel span
    b.addCube(v3(0, 5.60, 0), v3(6.9, 0.40, 1.05), STONE_LT); // upper course
    // chipped parapet stubs
    b.addCube(v3(-2.6, 5.98, 0), v3(0.9, 0.36, 0.9), STONE_DK);
    b.addCube(v3(-0.4, 5.92, 0.05), v3(0.7, 0.24, 0.8), STONE_DK);
    b.addCube(v3(2.4, 6.04, -0.04), v3(1.0, 0.48, 0.85), STONE);
    return b.toModel(shader);
}

// A ruined wall run: two masonry courses crumbling to broken merlons, moss on the
// survivors, rubble shed at the foot.
fn wallMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.addCube(v3(0, 0.6, 0), v3(7.0, 1.2, 0.85), STONE);
    b.addCube(v3(0.2, 1.55, 0), v3(6.2, 0.7, 0.75), STONE_DK);
    b.addCube(v3(-2.4, 2.25, 0), v3(1.1, 0.75, 0.70), STONE);
    b.addCube(v3(-2.4, 2.70, 0), v3(1.0, 0.16, 0.62), STONE_MOSS);
    b.addCube(v3(-0.6, 2.10, 0.02), v3(0.9, 0.45, 0.68), STONE_LT);
    b.addCube(v3(1.8, 2.35, -0.02), v3(1.2, 0.95, 0.72), STONE);
    b.addCube(v3(1.8, 2.90, 0), v3(1.05, 0.16, 0.6), STONE_MOSS);
    b.addCube(v3(3.4, 0.35, 0.9), v3(0.8, 0.7, 0.8), STONE_DK); // shed rubble
    b.addCube(v3(-3.3, 0.25, -0.75), v3(0.6, 0.5, 0.6), STONE_DK);
    return b.toModel(shader);
}

// A dead tree — bent trunk, bare clawing branches, root flare. The classic Lands
// Between silhouette against the haze.
fn treeMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.addCylinder(v3(0, 0, 0), v3(0.15, 1.7, 0.05), 0.24, 0.16, 7, BARK);
    b.addCylinder(v3(0.15, 1.7, 0.05), v3(0.42, 3.1, 0.12), 0.16, 0.09, 7, BARK);
    b.addCylinder(v3(0.42, 3.1, 0.12), v3(0.62, 4.15, 0.22), 0.09, 0.01, 6, BARK_DK); // top spike
    b.addCylinder(v3(0.15, 1.7, 0.05), v3(-0.95, 2.75, 0.35), 0.075, 0.01, 6, BARK_DK);
    b.addCylinder(v3(0.30, 2.5, 0.08), v3(1.35, 3.3, -0.42), 0.065, 0.01, 6, BARK_DK);
    b.addCylinder(v3(0.05, 0.95, 0.02), v3(-0.62, 1.35, -0.55), 0.06, 0.01, 6, BARK_DK);
    // root flare
    b.addCylinder(v3(0, 0.22, 0), v3(0.42, 0.0, 0.30), 0.10, 0.03, 5, BARK);
    b.addCylinder(v3(0, 0.22, 0), v3(-0.45, 0.0, 0.18), 0.10, 0.03, 5, BARK);
    b.addCylinder(v3(0, 0.22, 0), v3(0.05, 0.0, -0.48), 0.10, 0.03, 5, BARK);
    return b.toModel(shader);
}

// A grave cluster: two leaning headstones and one toppled flat, over low earth mounds.
fn gravesMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.addBox(v3(0, 0.42, 0), v3(0.28, 0, 0.02), v3(0.07, 0.42, 0.03), v3(0, 0.015, 0.075), STONE);
    b.addBox(v3(0.95, 0.33, -0.55), v3(0.22, 0, -0.03), v3(-0.10, 0.33, 0.02), v3(0.01, 0.02, 0.06), STONE_DK);
    b.addBox(v3(1.7, 0.07, 0.35), v3(0.26, 0, 0.05), v3(0, 0.06, 0.30), v3(-0.02, 0.02, 0.05), STONE_MOSS); // fallen flat
    b.addCube(v3(0, 0.06, 0.35), v3(0.6, 0.12, 0.7), STONE_MOSS); // mound
    b.addCube(v3(0.95, 0.05, -0.15), v3(0.5, 0.10, 0.6), STONE_MOSS);
    return b.toModel(shader);
}

// A sword left standing in the earth, blade down, leaning — steel cross, brass pommel.
fn swordMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    const d = v3(0.10, 0.90, 0.42); // unit-ish lean of the blade (point buried at origin)
    const p1 = v3(0.995, 0.090, 0.042); // ~perpendicular, edge direction
    const p2 = v3(0, -0.422, 0.9045); // ~perpendicular, flat direction
    const at = struct {
        fn along(dir: rl.Vector3, t: f32) rl.Vector3 {
            return v3(dir.x * t, dir.y * t, dir.z * t);
        }
    }.along;
    // blade: from just under the soil to the guard
    b.addBox(at(d, 0.42), v3(p1.x * 0.055, p1.y * 0.055, p1.z * 0.055), at(d, 0.50), v3(p2.x * 0.012, p2.y * 0.012, p2.z * 0.012), STEEL);
    // crossguard
    b.addBox(at(d, 0.95), v3(p1.x * 0.16, p1.y * 0.16, p1.z * 0.16), at(d, 0.025), v3(p2.x * 0.030, p2.y * 0.030, p2.z * 0.030), STEEL);
    // grip + pommel
    b.addCylinder(at(d, 0.975), at(d, 1.20), 0.030, 0.026, 6, IRON);
    b.addCube(at(d, 1.26), v3(0.075, 0.075, 0.075), BRASS);
    // disturbed earth at the point
    b.addCube(v3(0.02, 0.045, 0.02), v3(0.34, 0.09, 0.30), STONE_MOSS);
    return b.toModel(shader);
}

// The grace ember: an iron bowl on a stone foot, banked gold coals, and a thin rising
// wisp — the coals and wisp ride the EMISSIVE vertex-alpha channel, so they burn through
// shadow and haze like a beacon.
fn graceMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.addCylinder(v3(0, 0, 0), v3(0, 0.25, 0), 0.30, 0.36, 8, STONE_DK);
    b.addCylinder(v3(0, 0.25, 0), v3(0, 0.50, 0), 0.36, 0.50, 8, IRON);
    b.addCylinder(v3(0, 0.42, 0), v3(0, 0.56, 0), 0.42, 0.28, 8, EMBER); // banked coals
    b.addCylinder(v3(0, 0.55, 0), v3(0, 1.45, 0), 0.030, 0.002, 6, WISP); // rising wisp
    b.addCylinder(v3(0, 0.52, 0), v3(0, 0.95, 0), 0.055, 0.006, 6, WISP);
    // drifting motes
    b.addCube(v3(0.20, 0.85, 0.08), v3(0.022, 0.022, 0.022), WISP);
    b.addCube(v3(-0.13, 1.10, -0.10), v3(0.018, 0.018, 0.018), WISP);
    b.addCube(v3(0.08, 1.32, -0.14), v3(0.015, 0.015, 0.015), WISP);
    b.addCube(v3(-0.19, 0.68, 0.14), v3(0.02, 0.02, 0.02), WISP);
    return b.toModel(shader);
}

// A colossal broken keep for the horizon — stacked offset masses with a jagged crown.
// Lives at the world edge where the haze reduces it to a silhouette.
fn towerMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.addCube(v3(0, 4.0, 0), v3(6.4, 8.0, 6.4), STONE_DK);
    b.addCube(v3(0.3, 11.0, -0.2), v3(5.4, 6.0, 5.4), STONE);
    b.addCube(v3(-1.4, 15.6, -1.2), v3(2.4, 3.2, 2.2), STONE_DK); // crown shards
    b.addCube(v3(1.6, 14.9, 1.3), v3(2.0, 1.8, 2.0), STONE);
    b.addCube(v3(0.4, 14.5, -1.8), v3(1.4, 1.0, 1.3), STONE_LT);
    b.addCube(v3(4.6, 1.1, 2.4), v3(2.6, 2.2, 2.2), STONE_DK); // collapsed spill
    return b.toModel(shader);
}

// The colossal horizon gate the avenue points at — twin towers and a high broken span.
fn gateMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    for ([_]f32{ -7.5, 7.5 }) |x| {
        b.addCube(v3(x, 7.0, 0), v3(5.0, 14.0, 5.0), STONE_DK);
        b.addCube(v3(x, 15.0, 0), v3(4.2, 2.0, 4.2), STONE);
    }
    b.addCube(v3(0, 12.2, 0), v3(11.0, 2.6, 3.4), STONE_DK); // span
    b.addCube(v3(-2.6, 14.0, 0), v3(3.2, 1.0, 3.0), STONE); // broken crest
    b.addCube(v3(3.4, 13.8, 0), v3(2.2, 0.7, 2.8), STONE);
    return b.toModel(shader);
}

// A leaning war banner: bent pole, crossarm, and two ragged strips of faded crimson —
// the fallen army's colors, matching the hero's cape.
fn bannerMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.addCylinder(v3(0, 0, 0), v3(0.28, 3.15, 0.10), 0.055, 0.035, 6, BARK_DK); // pole
    b.addCylinder(v3(-0.24, 3.02, 0.08), v3(0.80, 3.10, 0.12), 0.028, 0.022, 5, BARK_DK); // crossarm
    // ragged cloth: two hanging strips of unequal length, slightly skewed
    b.addBox(v3(0.06, 2.32, 0.10), v3(0.235, 0, 0.012), v3(0.03, 0.72, 0.015), v3(0.002, 0.01, 0.022), CLOTH);
    b.addBox(v3(0.52, 2.52, 0.115), v3(0.16, 0, 0.010), v3(0.045, 0.52, 0.01), v3(0.002, 0.008, 0.02), CLOTH);
    b.addCube(v3(0.06, 0.09, 0.02), v3(0.42, 0.18, 0.38), STONE_DK); // anchoring stones
    return b.toModel(shader);
}

// A weathered headless sentinel: robed figure on a plinth, one arm lost, neck snapped —
// it watched the road once.
fn statueMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.addCube(v3(0, 0.3, 0), v3(1.5, 0.6, 1.5), STONE_DK); // plinth
    b.addCube(v3(0, 0.72, 0), v3(1.2, 0.24, 1.2), STONE);
    b.addCylinder(v3(0, 0.84, 0), v3(0, 2.35, 0), 0.46, 0.30, 8, STONE); // robe
    b.addCube(v3(0, 2.42, 0), v3(0.78, 0.22, 0.42), STONE); // shoulders
    b.addCylinder(v3(0, 2.53, 0), v3(0.04, 2.68, 0.02), 0.11, 0.09, 6, STONE_DK); // snapped neck
    b.addBox(v3(0.42, 2.05, 0.12), v3(0.09, 0, 0.02), v3(0.10, 0.38, 0.14), v3(0.01, 0.02, 0.09), STONE); // surviving arm, reaching
    b.addCube(v3(-0.52, 0.95, 0.28), v3(0.30, 0.24, 0.26), STONE_MOSS); // fallen arm chunk
    return b.toModel(shader);
}

// ── FLORA ── all plant meshes are grown from one seeded Rng (deterministic builds),
// blades as 4-sided tapered cylinders leaning off vertical, bases on Y=0. Shot-verified
// and tuned against ER Limgrave: moderate scatter density (SCATTER), a mix weighted toward
// legible flowers/reeds, a graveyard flower ring + an east reed bed for composition. Flora
// are NON-casters (drawProps/drawFlora split) — excluded from the shadow map so thin blades
// don't sparkle — and they SWAY via the scene shader's height-based wind term (gfx.setWind;
// windAmt gates it to flora only, so gaits/props stay rigid).

// Fill the tail of e.props with the meadow scatter: rejection-sample positions that
// stay off the worn path (|x| small) and clear of every hand-placed prop's base.
fn scatterPlants(e: *Env) void {
    var rng = mathx.Rng.init(20260722);
    var n: usize = layout.len;
    var attempts: u32 = 0;
    while (n < e.props.len and attempts < 30000) : (attempts += 1) {
        const x = rng.range(-42, 42);
        const z = rng.range(-50, 34);
        if (@abs(x) < 3.4) continue; // the path (and the --shot runway) stays clear
        var ok = true;
        for (layout) |p| {
            const dx = x - p.x;
            const dz = z - p.z;
            if (dx * dx + dz * dz < 1.8 * 1.8) {
                ok = false;
                break;
            }
        }
        if (!ok) continue;
        const roll = rng.float();
        // 30% patch / 22% tuft / 18% reeds / 12% shrub / 18% flowers — reeds & flowers
        // weighted up from the first pass so they read at distance, not just grass tufts.
        const kind: u8 = if (roll < 0.30) K_PATCH else if (roll < 0.52) K_TUFT else if (roll < 0.70) K_REEDS else if (roll < 0.82) K_SHRUB else K_FLOWERS;
        e.props[n] = .{ .kind = kind, .pos = mathx.ground(x, z), .yaw = rng.range(0, 360), .scale = rng.range(0.75, 1.35) };
        n += 1;
    }
    // Rejection budget exhausted (practically unreachable): pad with a ring of tufts so
    // no prop slot is ever left undefined.
    while (n < e.props.len) : (n += 1) {
        const a = @as(f32, @floatFromInt(n)) * 0.61;
        e.props[n] = .{ .kind = K_TUFT, .pos = mathx.ground(30 * mathx.cosf(a), 28 * mathx.sinf(a)), .yaw = 0, .scale = 1.0 };
    }
}

// One grass blade: a thin 4-sided tapered cylinder leaning outward.
fn blade(b: *Builder, x: f32, z: f32, h: f32, lx: f32, lz: f32, r: f32, col: rl.Color) void {
    b.addCylinder(v3(x, 0, z), v3(x + lx, h, z + lz), r, 0.003, 4, col);
}

fn bladeColor(rng: *mathx.Rng) rl.Color {
    const roll = rng.float();
    if (roll < 0.5) return GRASS_GOLD;
    if (roll < 0.8) return GRASS_DRY;
    return GRASS_GRN;
}

// Grow one clump of blades (plus the odd seed stalk) around (cx, cz) into b.
fn tuftInto(b: *Builder, rng: *mathx.Rng, cx: f32, cz: f32, s: f32) void {
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
        // a taller seed stalk rising out of the clump
        const la = rng.angle();
        const lean = rng.range(0.04, 0.12) * s;
        const h = rng.range(0.55, 0.8) * s;
        const tx = cx + mathx.cosf(la) * lean;
        const tz = cz + mathx.sinf(la) * lean;
        blade(b, cx, cz, h, mathx.cosf(la) * lean, mathx.sinf(la) * lean, 0.012 * s, GRASS_DRY);
        b.addCube(v3(tx, h, tz), v3(0.035 * s, 0.09 * s, 0.035 * s), SEED);
    }
}

// A single golden grass clump.
fn tuftMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(11);
    tuftInto(&b, &rng, 0, 0, 1.0);
    return b.toModel(shader);
}

// A wide swathe: several clumps strewn across ~2.5 m.
fn patchMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(23);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.2, 1.25);
        tuftInto(&b, &rng, mathx.cosf(a) * d, mathx.sinf(a) * d, rng.range(0.7, 1.1));
    }
    return b.toModel(shader);
}

// Low dark scrub: tilted foliage masses over a few bare twigs.
fn shrubMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.addBox(v3(0, 0.28, 0), v3(0.42, 0.04, 0.06), v3(-0.05, 0.26, 0.04), v3(0.05, 0.03, 0.38), SCRUB);
    b.addBox(v3(0.3, 0.2, 0.22), v3(0.3, -0.03, 0.05), v3(0.04, 0.18, -0.03), v3(-0.04, 0.02, 0.26), SCRUB_DK);
    b.addBox(v3(-0.28, 0.18, -0.15), v3(0.26, 0.05, -0.04), v3(-0.03, 0.17, 0.05), v3(0.05, -0.02, 0.24), SCRUB);
    b.addCylinder(v3(0.1, 0.1, 0.05), v3(0.5, 0.62, 0.2), 0.02, 0.004, 4, BARK_DK);
    b.addCylinder(v3(-0.05, 0.1, 0), v3(-0.38, 0.55, -0.28), 0.02, 0.004, 4, BARK_DK);
    var rng = mathx.Rng.init(37);
    tuftInto(&b, &rng, 0.45, -0.35, 0.7); // grass at the skirt
    return b.toModel(shader);
}

// Pale erdleaf-like blooms nodding over a grass clump.
fn flowersMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(53);
    tuftInto(&b, &rng, 0, 0, 0.8);
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.05, 0.30);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.26, 0.44);
        b.addCylinder(v3(x, 0, z), v3(x, h, z), 0.009, 0.005, 4, STEM);
        b.addCube(v3(x, h + 0.02, z), v3(0.07, 0.05, 0.07), PETAL); // fatter bloom — reads at distance
    }
    return b.toModel(shader);
}

// Tall dry sedge, seed heads riding the tips.
fn reedsMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(71);
    var i: i32 = 0;
    while (i < 7) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.03, 0.22);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const la = rng.angle();
        const lean = rng.range(0.05, 0.16);
        const h = rng.range(0.75, 1.25);
        const lx = mathx.cosf(la) * lean;
        const lz = mathx.sinf(la) * lean;
        blade(&b, x, z, h, lx, lz, 0.016, if (rng.float() < 0.7) GRASS_DRY else GRASS_GOLD);
        b.addCube(v3(x + lx, h + 0.03, z + lz), v3(0.038, 0.13, 0.038), SEED); // fuller seed head
    }
    return b.toModel(shader);
}

// Grace-side blooms: taller pale flowers with a faint emissive glow.
fn glowMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    var rng = mathx.Rng.init(89);
    tuftInto(&b, &rng, 0, 0, 0.75);
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        const a = rng.angle();
        const d = rng.range(0.06, 0.2);
        const x = mathx.cosf(a) * d;
        const z = mathx.sinf(a) * d;
        const h = rng.range(0.32, 0.5);
        b.addCylinder(v3(x, 0, z), v3(x, h, z), 0.008, 0.005, 4, STEM);
        b.addCube(v3(x, h + 0.025, z), v3(0.05, 0.04, 0.05), PETAL_GLOW);
    }
    return b.toModel(shader);
}

// Low rubble scatter — shattered drum bits half-sunk by the path.
fn rubbleMesh(shader: rl.Shader) rl.Model {
    var b = Builder.init();
    b.addCube(v3(0, 0.16, 0), v3(0.55, 0.34, 0.45), STONE_DK);
    b.addCube(v3(0.65, 0.10, 0.3), v3(0.35, 0.22, 0.3), STONE);
    b.addCube(v3(-0.5, 0.09, -0.25), v3(0.3, 0.18, 0.35), STONE_MOSS);
    b.addCylinder(v3(-0.15, 0.14, 0.65), v3(0.45, 0.14, 0.95), 0.16, 0.14, 6, STONE_LT); // drum shard
    return b.toModel(shader);
}
