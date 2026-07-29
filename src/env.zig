const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const collision = @import("collision.zig");
const props = @import("props.zig");

const v3 = mathx.v3;
const Kind = props.Kind;

// ── THE WORLD ── a golden-hour plain, 320 m on a side, ringed by cliffs, holding five
// regions that each read differently the moment you walk into them:
//
//   CENTRE/SOUTH  the fallen avenue you start on — colonnade, gate arch, grace ember
//   NORTH         THE FALLEN CITY: plaza, ruined perimeter, a torchlit CHAPEL you enter,
//                 watchtowers, carts abandoned on the road, the colossal horizon gate
//   EAST          THE TARN: a shallow lake you WADE, drowned columns, a collapsed
//                 causeway leading out into it, willows and reed beds
//   WEST          THE OLD WOOD: great trees, ferns and brambles, a standing-stone circle,
//                 a woodcutter's cottage with its campfire still ringed in stone
//   SOUTH         THE WINDSWEPT DOWNS: open, sparse, lone trees, a watchtower on the rise
//
// PERFORMANCE — the whole point of the structure below. Thousands of props, most of them behind
// you or lost in haze, so:
//
//   1. A UNIFORM GRID indexes every prop by cell (CSR: one items array + per-cell spans, no
//      allocation). Two indexes — structures and flora — so each pass walks only its own, and
//      each cell carries the maxima that pass needs.
//   2. The LIT PASS culls per CELL first (four frustum side planes + the cell's max view
//      distance), then per prop. A rejected cell is 30 props never touched.
//   3. The DEPTH PASS culls by SHADOW REACH, not camera distance: at this sun elevation a
//      caster throws its shadow ~1.5x its height sideways, so a prop matters iff its footprint
//      plus that reach can touch the sun's ortho box. A naive distance cull clips real shadows;
//      this is the version that doesn't.
//   4. COLLISION and ARROW FLIGHT query the same grid instead of scanning every solid.
//
// All static and deterministic — every scatter runs off a seeded mathx.Rng, so the world is
// identical every launch and --shot stays comparable frame to frame.

pub const HALF: f32 = 160.0; // playable bounds span [-HALF, +HALF] on X and Z
// The ground QUAD extends far past the bounds so the terrain runs all the way into full
// distance haze — no visible plane edge / sky band below the horizon, from anywhere.
const GROUND_HALF: f32 = 360.0;
const CLIFF_EDGE: f32 = HALF + 6.0; // the rock wall stands just outside the movement clamp

// Storage caps. All fixed — Env is one flat block inside the heap-allocated Game, never
// allocates, and never resizes. Overflowing any of them is a BUILD-TIME (well, init-time)
// panic rather than a silent drop, because a silently dropped collider is a walk-through wall
// and a silently dropped prop is a hole in the world.
const MAX_PROPS = 24576;
const MAX_SOLIDS = 8192;
const MAX_SOLID_REFS = 4 * MAX_SOLIDS; // a long solid's bbox spans several cells, one ref each
const MAX_LIGHTS = 192; // fires in the world; gfx.MAX_LIGHTS of them reach the GPU per frame

// The grid. CELL is a compromise: small enough that a cell is a meaningful cull unit, large
// enough that the per-cell overhead (576 cells walked per pass) stays trivial.
const CELL: f32 = 16.0;
const GRID_N: usize = 24;
const GRID_SPAN: f32 = CELL * @as(f32, @floatFromInt(GRID_N)); // 384 — covers the cliff ring with room over
const GRID_HALF: f32 = GRID_SPAN * 0.5;
const NCELL: usize = GRID_N * GRID_N;
// Half-diagonal of a square of side 1 — the factor that turns a square's half-width into the
// radius of the sphere enclosing it. Named because it appears twice (cell circumradius and the
// shadow box's), and 0.70711 written out twice reads like two unrelated magic numbers.
const HALF_DIAG: f32 = @sqrt(0.5);
const CELL_CIRCUM: f32 = CELL * HALF_DIAG; // centre-to-corner of a cell, for sphere tests

// Horizontal distance a shadow travels per unit of caster height, from THE one sun direction
// (gfx.SUN_DIR) — so retuning the light can't leave this stale.
const SUN_REACH: f32 = @sqrt(gfx.SUN_DIR.x * gfx.SUN_DIR.x + gfx.SUN_DIR.z * gfx.SUN_DIR.z) / gfx.SUN_DIR.y;
// Half-diagonal of the sun's ortho box: a caster outside this (plus its reach) cannot put a
// single texel into the shadow map.
const SHADOW_BOX: f32 = gfx.SHADOW_ORTHO * HALF_DIAG;

// Largest number of solids one grid query can hand back. A 16 m cell in the densest spot (the
// watchtower's 11-collider drum plus its spill) holds well under 30, and a query straddles at
// most four cells.
pub const MAX_NEAR = 160;

// The ground sits a HAIR ABOVE Y=0 (where soles / prop bases are authored) so nothing ever
// reads as FLOATING: content is planted-to-slightly-embedded instead. The old -0.05 dropped
// the ground BELOW the feet, which floated everything ~2 in. Owner's call: a tiny foot clip on
// the run-crouch / roll is preferred over any float. Kept off exact 0 so coplanar faces don't
// z-fight; kept tiny (~1 cm) so the embed is imperceptible.
const GROUND_Y: f32 = 0.01;

const Prop = struct { kind: Kind, pos: rl.Vector3, yaw: f32, scale: f32 };

// A fire's static description; the per-frame guttering is applied in uploadLights.
const WorldLight = struct { base: gfx.Light, flicker: f32, phase: f32 };

// A water sheet, remembered so the scatter doesn't grow grass in the middle of the lake and
// so future systems (wading FX, sound) have somewhere to ask.
const Pool = struct { pos: rl.Vector3, radius: f32 };

// One CSR spatial index over a subset of the prop list. `items` holds prop indices grouped by
// cell; `start[c]..start[c+1]` is cell c's run. The three per-cell maxima let a whole cell be
// accepted or rejected before any prop in it is looked at.
const Index = struct {
    start: [NCELL + 1]u32 = [_]u32{0} ** (NCELL + 1),
    items: [MAX_PROPS]u32 = undefined,
    bound: [NCELL]f32 = [_]f32{0} ** NCELL, // max scaled bounding radius in the cell
    view: [NCELL]f32 = [_]f32{0} ** NCELL, // max view distance in the cell
    top: [NCELL]f32 = [_]f32{0} ** NCELL, // max scaled top height (shadow reach)
};

/// The camera's four frustum SIDE planes, all through the eye point, plus that point. Near and
/// far are handled by the per-kind view distance instead, which is stricter and cheaper.
///
/// Built from the camera BASIS rather than by extracting planes from a view-projection matrix:
/// same result, none of raylib's row/column-major ambiguity to get wrong, and it unit-tests
/// with a pencil.
pub const View = struct {
    pos: rl.Vector3,
    n: [4]rl.Vector3, // inward normals: left, right, top, bottom

    pub fn fromCamera(cam: rl.Camera3D, aspect: f32) View {
        const fwd = mathx.normV(mathx.subV(cam.target, cam.position));
        // NB this camera's screen-right is world −X when looking down +Z (see AGENTS.md's
        // strafe-sign invariant), so (right, up, fwd) is not the handedness you'd assume. The
        // plane normals below are therefore sign-corrected against `fwd` rather than derived
        // from an assumed handedness — the first version of this assumed one and culled the
        // ENTIRE world, which is exactly the bug a hand-derived cross product invites.
        const right = mathx.normV(cross(fwd, cam.up));
        const up = cross(right, fwd);
        // A couple of degrees of slack: a plane that hugs the frustum exactly will pop a prop
        // whose authored `bound` is a touch tight, and the cost of the slack is a few draws.
        const vf = mathx.radians(cam.fovy) * 0.5 + mathx.radians(2.5);
        const hf = std.math.atan(@tan(mathx.radians(cam.fovy) * 0.5) * aspect) + mathx.radians(2.5);
        const cv = mathx.cosf(vf);
        const sv = mathx.sinf(vf);
        const chz = mathx.cosf(hf);
        const shz = mathx.sinf(hf);
        // Each boundary DIRECTION (a ray along one edge of the frustum's cross-section), then
        // the plane it spans with the axis it hinges about.
        const dl = mathx.addV(mathx.scaleV(fwd, chz), mathx.scaleV(right, -shz));
        const dr = mathx.addV(mathx.scaleV(fwd, chz), mathx.scaleV(right, shz));
        const dt = mathx.addV(mathx.scaleV(fwd, cv), mathx.scaleV(up, sv));
        const db = mathx.addV(mathx.scaleV(fwd, cv), mathx.scaleV(up, -sv));
        return .{ .pos = cam.position, .n = .{
            inward(up, dl, fwd),
            inward(up, dr, fwd),
            inward(right, dt, fwd),
            inward(right, db, fwd),
        } };
    }

    /// Is the sphere (c, rad) worth drawing — inside all four side planes and within maxDist?
    pub fn visible(self: *const View, c: rl.Vector3, rad: f32, maxDist: f32) bool {
        const d = mathx.subV(c, self.pos);
        const far = maxDist + rad;
        if (d.x * d.x + d.y * d.y + d.z * d.z > far * far) return false;
        for (self.n) |nn| {
            if (nn.x * d.x + nn.y * d.y + nn.z * d.z < -rad) return false;
        }
        return true;
    }
};

/// Which set of props a draw call wants, and the test that decides.
pub const Cull = union(enum) {
    /// The lit pass: the camera frustum + each kind's own view distance.
    view: View,
    /// The sun depth pass: the hero-tracking focus point of the shadow ortho box.
    sun: rl.Vector3,
};

pub const Env = struct {
    ground: rl.Model,
    models: [props.NK]rl.Model,
    props: [MAX_PROPS]Prop = undefined,
    nprops: usize = 0,
    solid_buf: [MAX_SOLIDS]collision.Solid = undefined,
    nsolids: usize = 0,
    // Structures and flora are indexed separately: the two draw passes then share nothing and
    // neither pays to skip the other's props.
    stx: Index = .{},
    flx: Index = .{},
    // Solid grid: refs into solid_buf, a solid appearing in every cell its footprint touches.
    sgrid_start: [NCELL + 1]u32 = [_]u32{0} ** (NCELL + 1),
    sgrid_items: [MAX_SOLID_REFS]u32 = undefined,
    lights: [MAX_LIGHTS]WorldLight = undefined,
    nlights: usize = 0,
    pools: [8]Pool = undefined,
    npools: usize = 0,
    // Per-frame culling counters, surfaced by the debug Stats overlay. The whole expansion rests
    // on the claim that a world of thousands of props costs a few hundred draws, and this is what
    // makes that claim CHECKABLE while playing instead of a thing I asserted once in a comment.
    stat_draws: u32 = 0,
    stat_cells: u32 = 0,

    /// Build the world IN PLACE. Not an `init()` returning a value: Env is ~450 KB of flat
    /// arrays, and a by-value return would copy that through the stack twice.
    pub fn build(self: *Env, shader: rl.Shader) void {
        // Index each mesh by its own kind so the array and the kinds can't drift out of
        // lockstep (props.INFO's comptime block already pins the table; this pins the models).
        for (&self.models, props.INFO) |*m, row| m.* = row.build(shader);
        self.ground = terrain(shader, GROUND_HALF);
        self.nprops = 0;
        self.nsolids = 0;
        self.nlights = 0;
        self.npools = 0;

        var p = Placer{ .e = self, .rng = mathx.Rng.init(20260728) };
        avenue(&p); // the start: unchanged from the 120 m world, runway included
        fallenCity(&p);
        theTarn(&p);
        oldWood(&p);
        theDowns(&p);
        cliffRing(&p);
        buildSolids(self); // …before the scatter, which asks the solid grid where it may grow
        scatterFlora(&p);
        indexProps(self);
    }

    /// Every solid in the world — for whole-world work (tests, tooling). Gameplay must use
    /// nearSolids/resolveActor: this list is ~700 long and scanning it per actor per frame is
    /// exactly what the grid exists to avoid.
    pub fn solids(self: *const Env) []const collision.Solid {
        return self.solid_buf[0..self.nsolids];
    }

    /// The solids that could touch a circle of radius `r` about `p`, written into `out`.
    /// Conservative: it may hand back a few extra (cell granularity), never fewer.
    pub fn nearSolids(self: *const Env, p: rl.Vector3, r: f32, out: []collision.Solid) []const collision.Solid {
        var n: usize = 0;
        const lo = cellCoord(p.x - r);
        const hi = cellCoord(p.x + r);
        const zlo = cellCoord(p.z - r);
        const zhi = cellCoord(p.z + r);
        var cz = zlo;
        while (cz <= zhi) : (cz += 1) {
            var cx = lo;
            while (cx <= hi) : (cx += 1) {
                const c = cz * GRID_N + cx;
                var k = self.sgrid_start[c];
                while (k < self.sgrid_start[c + 1]) : (k += 1) {
                    if (n >= out.len) return out[0..n]; // MAX_NEAR is sized well past the densest cell
                    out[n] = self.solid_buf[self.sgrid_items[k]];
                    n += 1;
                }
            }
        }
        return out[0..n];
    }

    /// Push an actor's footprint out of the nearby world solids (the grid-local counterpart of
    /// collision.resolve).
    pub fn resolveActor(self: *const Env, p: rl.Vector3, r: f32) rl.Vector3 {
        var buf: [MAX_NEAR]collision.Solid = undefined;
        return collision.resolve(p, r, self.nearSolids(p, r + 1.0, &buf));
    }

    /// Water depth-ish test: is this ground position inside a pool? (Nothing blocks there —
    /// the tarn is wadeable by design — but the scatter uses it, and wading FX will too.)
    pub fn inWater(self: *const Env, x: f32, z: f32, inset: f32) bool {
        for (self.pools[0..self.npools]) |w| {
            const dx = x - w.pos.x;
            const dz = z - w.pos.z;
            const r = w.radius * inset;
            if (dx * dx + dz * dz < r * r) return true;
        }
        return false;
    }

    pub fn setShader(self: *Env, sh: rl.Shader) void {
        self.ground.materials[0].shader = sh;
        for (&self.models) |*m| m.materials[0].shader = sh;
    }

    // Terrain receives shadows but doesn't cast; drawn separately with groundMode on.
    pub fn drawGround(self: *const Env) void {
        rl.drawModel(self.ground, mathx.zero3, 1.0, rl.Color.white);
    }

    /// The stone/structure props — the shadow casters, drawn in BOTH passes through this ONE
    /// function so their transforms can never drift between the depth pass and the lit pass
    /// (only the SET differs, which is the whole point of culling).
    pub fn drawProps(self: *Env, cull: Cull) void {
        self.drawIndexed(&self.stx, cull);
    }

    /// Zero the culling counters — call once at the top of the frame, before either pass.
    pub fn resetStats(self: *Env) void {
        self.stat_draws = 0;
        self.stat_cells = 0;
    }

    /// Props in the world, for the debug overlay (the denominator for stat_draws).
    pub fn propCount(self: *const Env) usize {
        return self.nprops;
    }
    pub fn solidCount(self: *const Env) usize {
        return self.nsolids;
    }
    pub fn lightCount(self: *const Env) usize {
        return self.nlights;
    }

    /// The flora — non-casters (thin blades sparkle in a shadow map), drawn only in the lit
    /// pass with the wind term on.
    pub fn drawFlora(self: *Env, view: *const View) void {
        self.drawIndexed(&self.flx, .{ .view = view.* });
    }

    // Walk one index cell by cell, rejecting whole cells before touching their props.
    fn drawIndexed(self: *Env, idx: *const Index, cull: Cull) void {
        // The depth pass wants CASTERS only; the lit pass wants everything, non-casters (the
        // water sheet) included — skipping them there would simply delete the tarn.
        const casters_only = cull == .sun;
        var c: usize = 0;
        while (c < NCELL) : (c += 1) {
            if (idx.start[c] == idx.start[c + 1]) continue;
            const centre = cellCentre(c);
            switch (cull) {
                .view => |*vw| {
                    if (!vw.visible(centre, CELL_CIRCUM + idx.bound[c], idx.view[c])) continue;
                },
                .sun => |focus| {
                    if (!castsInto(focus, centre, CELL_CIRCUM + idx.bound[c], idx.top[c])) continue;
                },
            }
            self.stat_cells += 1;
            var k = idx.start[c];
            while (k < idx.start[c + 1]) : (k += 1) {
                const pr = &self.props[idx.items[k]];
                const nfo = props.info(pr.kind);
                if (casters_only and !nfo.casts) continue;
                const bound = nfo.bound * pr.scale;
                switch (cull) {
                    .view => |*vw| {
                        if (!vw.visible(pr.pos, bound, nfo.view)) continue;
                    },
                    .sun => |focus| {
                        if (!castsInto(focus, pr.pos, bound, nfo.top * pr.scale)) continue;
                    },
                }
                self.stat_draws += 1;
                rl.drawModelEx(self.models[@intFromEnum(pr.kind)], pr.pos, v3(0, 1, 0), pr.yaw, v3(pr.scale, pr.scale, pr.scale), rl.Color.white);
            }
        }
    }

    /// Push this frame's torch/fire lights: the gfx.MAX_LIGHTS nearest the camera, each with
    /// its guttering applied. The world may hold far more than the shader can hold; the ones
    /// dropped are the furthest away, where a light contributes nothing anyway.
    pub fn uploadLights(self: *const Env, scene: *gfx.Scene, camPos: rl.Vector3, t: f32) void {
        var picked: [gfx.MAX_LIGHTS]gfx.Light = undefined;
        var dist: [gfx.MAX_LIGHTS]f32 = undefined;
        var n: usize = 0;
        for (self.lights[0..self.nlights]) |wl| {
            const d2 = mathx.dist2XZ(wl.base.pos, camPos);
            // Past its own radius plus a bit, a light cannot reach anything on screen near the
            // camera; that alone throws away most of the world's fires.
            if (d2 > (wl.base.radius + 90.0) * (wl.base.radius + 90.0)) continue;
            const k = 1.0 + wl.flicker * gutter(t, wl.phase);
            const lit = gfx.Light{
                .pos = wl.base.pos,
                .col = mathx.scaleV(wl.base.col, mathx.maxF(k, 0.05)),
                .radius = wl.base.radius,
            };
            if (n < picked.len) {
                picked[n] = lit;
                dist[n] = d2;
                n += 1;
                continue;
            }
            // Full: replace the furthest, if this one is nearer.
            var worst: usize = 0;
            for (dist[0..n], 0..) |dd, i| {
                if (dd > dist[worst]) worst = i;
            }
            if (d2 < dist[worst]) {
                picked[worst] = lit;
                dist[worst] = d2;
            }
        }
        scene.setLights(picked[0..n]);
    }
};

// A flame's guttering, in [-1, 1]: three incommensurate rates so it never reads as a pulse.
fn gutter(t: f32, phase: f32) f32 {
    return 0.55 * mathx.sinf(t * 9.1 + phase) + 0.28 * mathx.sinf(t * 19.7 + phase * 2.3) + 0.17 * mathx.sinf(t * 4.3 + phase * 0.6);
}

// Does a caster at `pos` (bounding radius `bound`, height `top`) reach the sun's ortho box
// around `focus`? Distance is XZ-only: the box tracks the hero on the ground plane.
fn castsInto(focus: rl.Vector3, pos: rl.Vector3, bound: f32, top: f32) bool {
    const reach = SHADOW_BOX + bound + top * SUN_REACH;
    return mathx.dist2XZ(focus, pos) <= reach * reach;
}

fn cross(a: rl.Vector3, b: rl.Vector3) rl.Vector3 {
    return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}

// The unit normal of the plane spanned by `a` and `b`, flipped to point to the side `inside`
// is on. Used for the frustum's side planes with `inside` = the camera forward, which is by
// construction strictly within all four of them — so the sign is DERIVED rather than assumed,
// and a basis whose handedness surprises you can no longer invert the whole culler.
fn inward(a: rl.Vector3, b: rl.Vector3, inside: rl.Vector3) rl.Vector3 {
    const n = mathx.normV(cross(a, b));
    const d = n.x * inside.x + n.y * inside.y + n.z * inside.z;
    return if (d < 0) mathx.scaleV(n, -1) else n;
}

// World coordinate → grid column/row, clamped so anything outside the grid lands in the edge
// cell rather than indexing out of bounds (the cliff ring sits near the limit by design).
fn cellCoord(w: f32) usize {
    const f = (w + GRID_HALF) / CELL;
    if (f <= 0) return 0;
    const i: usize = @intFromFloat(f);
    return @min(i, GRID_N - 1);
}

fn cellOf(x: f32, z: f32) usize {
    return cellCoord(z) * GRID_N + cellCoord(x);
}

fn cellCentre(c: usize) rl.Vector3 {
    const cx = c % GRID_N;
    const cz = c / GRID_N;
    return v3(
        (@as(f32, @floatFromInt(cx)) + 0.5) * CELL - GRID_HALF,
        0,
        (@as(f32, @floatFromInt(cz)) + 0.5) * CELL - GRID_HALF,
    );
}

// Flat ground plane as one big white quad — the scene shader's terrainAlbedo owns the look.
fn terrain(shader: rl.Shader, half: f32) rl.Model {
    var b = gfx.Builder.init();
    b.quad(v3(-half, GROUND_Y, -half), v3(-half, GROUND_Y, half), v3(half, GROUND_Y, half), v3(half, GROUND_Y, -half), v3(0, 1, 0), rl.Color.white);
    return b.toModel(shader);
}

// ── placement ──────────────────────────────────────────────────────────────────────────
// Regions are AUTHORED IN CODE rather than as one giant coordinate table: a region is a
// paragraph you can read ("a ring of nine standing stones, one missing"), the seeded jitter
// keeps it wabi-sabi, and a table of four thousand rows is not something anyone can edit.

const Placer = struct {
    e: *Env,
    rng: mathx.Rng,

    fn at(self: *Placer, kind: Kind, x: f32, z: f32, yaw: f32, scale: f32) void {
        self.atY(kind, x, 0, z, yaw, scale);
    }

    // With an explicit Y — only water uses it, to stagger overlapping sheets out of z-fighting.
    fn atY(self: *Placer, kind: Kind, x: f32, y: f32, z: f32, yaw: f32, scale: f32) void {
        if (self.e.nprops >= MAX_PROPS) @panic("env: MAX_PROPS exceeded — raise the cap");
        self.e.props[self.e.nprops] = .{ .kind = kind, .pos = v3(x, y, z), .yaw = yaw, .scale = scale };
        self.e.nprops += 1;
        if (props.info(kind).light) |ls| self.addLight(x, y, z, scale, ls);
        if (kind == .water) {
            // An init-time PANIC, like MAX_PROPS/MAX_SOLIDS — never a silent drop. A dropped pool
            // makes `inWater` lie about that sheet, and the flora scatter then grows grass and
            // brambles out in the middle of the lake.
            if (self.e.npools >= self.e.pools.len) @panic("env: water pool cap exceeded — raise Env.pools");
            self.e.pools[self.e.npools] = .{ .pos = v3(x, y, z), .radius = 13.0 * scale };
            self.e.npools += 1;
        }
    }

    fn addLight(self: *Placer, x: f32, y: f32, z: f32, scale: f32, ls: props.LightSpec) void {
        if (self.e.nlights >= MAX_LIGHTS) return; // fires past the cap simply don't light — never a crash
        self.e.lights[self.e.nlights] = .{
            .base = .{ .pos = v3(x, y + ls.y * scale, z), .col = ls.col, .radius = ls.radius * mathx.maxF(scale, 0.6) },
            .flicker = ls.flicker,
            .phase = self.rng.range(0, 60), // every flame guttering on its own beat
        };
        self.e.nlights += 1;
    }

    // Jittered placement: the workhorse. Spread is the positional wobble, s the scale band.
    fn jit(self: *Placer, kind: Kind, x: f32, z: f32, spread: f32, sLo: f32, sHi: f32) void {
        self.at(
            kind,
            x + self.rng.signed() * spread,
            z + self.rng.signed() * spread,
            self.rng.range(0, 360),
            self.rng.range(sLo, sHi),
        );
    }

    // A scattered belt of one kind in a box, skipping the start runway, open water, and the
    // world's CLEARINGS (`coverField`, mixed toward 1 so structures thin where the flora does
    // without vanishing). `n` is an attempt count, not a guarantee — rejection keeps the world
    // honest, and clumping keeps it from looking sown.
    fn belt(self: *Placer, kind: Kind, x0: f32, z0: f32, x1: f32, z1: f32, n: i32, sLo: f32, sHi: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            const x = self.rng.range(x0, x1);
            const z = self.rng.range(z0, z1);
            if (onRunway(x, z)) continue;
            if (self.e.inWater(x, z, 1.04)) continue;
            if (self.rng.float() > 0.35 + 0.65 * coverField(x, z)) continue;
            self.at(kind, x, z, self.rng.range(0, 360), self.rng.range(sLo, sHi));
        }
    }

    // One of a SET of kinds, picked at random — for props that exist in variants (the great
    // trees) so a region mixes them instead of repeating one silhouette.
    fn anyOf(self: *Placer, kinds: []const Kind) Kind {
        return kinds[@intCast(self.rng.intn(@intCast(kinds.len)))];
    }

    // A ring of props about a centre — henges, stone circles, camps.
    fn ring(self: *Placer, kind: Kind, cx: f32, cz: f32, radius: f32, n: i32, skip: i32, sLo: f32, sHi: f32) void {
        var i: i32 = 0;
        while (i < n) : (i += 1) {
            if (i == skip) continue; // the gap: a ring with every stone present reads as a fence
            const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
            const r = radius * self.rng.range(0.94, 1.06);
            self.at(
                kind,
                cx + mathx.cosf(a) * r,
                cz + mathx.sinf(a) * r,
                mathx.degrees(-a) + 90 + self.rng.signed() * 12, // faces the centre, roughly
                self.rng.range(sLo, sHi),
            );
        }
    }
};

// The hero's runway (x ≈ 0, z 26 → -40) is the --shot travel lane and the live start: it stays
// clear of everything, so a straight walk out of the grace is never blocked by a scatter.
fn onRunway(x: f32, z: f32) bool {
    return @abs(x) < 3.4 and z > -44 and z < 30;
}

// ── CENTRE: the fallen avenue (the original hand composition, unchanged) ────────────────
const P = struct { x: f32, z: f32, yaw: f32, s: f32, kind: Kind };
const avenue_layout = [_]P{
    // colonnade avenue flanking the path
    .{ .x = -6, .z = 14, .yaw = 8, .s = 0.9, .kind = .broken },
    .{ .x = 6, .z = 12, .yaw = 0, .s = 1.0, .kind = .pillar },
    .{ .x = -6, .z = -6, .yaw = 0, .s = 1.0, .kind = .pillar },
    .{ .x = 6, .z = -6, .yaw = 0, .s = 1.1, .kind = .pillar },
    .{ .x = -6, .z = -16, .yaw = 0, .s = 1.0, .kind = .broken },
    .{ .x = 6, .z = -16, .yaw = 12, .s = 1.0, .kind = .pillar },
    .{ .x = -6, .z = -26, .yaw = 0, .s = 0.95, .kind = .pillar },
    .{ .x = 6, .z = -26, .yaw = 0, .s = 1.05, .kind = .broken },
    .{ .x = -6, .z = -36, .yaw = -6, .s = 1.05, .kind = .pillar },
    .{ .x = 6, .z = -36, .yaw = 20, .s = 0.95, .kind = .broken },
    // the gate arch over the path
    .{ .x = 0, .z = -31, .yaw = 0, .s = 1.0, .kind = .arch },
    // the grace ember, just off the path by the start
    .{ .x = 3.0, .z = 6.5, .yaw = 0, .s = 1.0, .kind = .grace },
    // ruined walls
    .{ .x = -14, .z = -14, .yaw = 78, .s = 1.1, .kind = .wall },
    .{ .x = 15, .z = -40, .yaw = -12, .s = 1.2, .kind = .wall },
    .{ .x = -24, .z = -28, .yaw = 100, .s = 0.9, .kind = .wall },
    // dead trees
    .{ .x = -12, .z = -2, .yaw = 0, .s = 1.1, .kind = .tree },
    .{ .x = 16, .z = -31, .yaw = 140, .s = 1.3, .kind = .tree },
    .{ .x = -20, .z = -38, .yaw = 70, .s = 0.9, .kind = .tree },
    .{ .x = 24, .z = 6, .yaw = 200, .s = 1.0, .kind = .tree },
    // graveyard cluster + a stray marker
    .{ .x = -11, .z = -29, .yaw = 15, .s = 1.0, .kind = .graves },
    .{ .x = -14, .z = -33, .yaw = -40, .s = 0.9, .kind = .graves },
    .{ .x = 13, .z = -26, .yaw = 60, .s = 0.8, .kind = .graves },
    // swords left standing in the earth
    .{ .x = -2.8, .z = -21, .yaw = 30, .s = 1.0, .kind = .sword },
    .{ .x = 10, .z = -8, .yaw = -70, .s = 0.9, .kind = .sword },
    .{ .x = -12.5, .z = -31, .yaw = 120, .s = 1.1, .kind = .sword },
    // ruin blocks
    .{ .x = 15, .z = -3, .yaw = -25, .s = 1.3, .kind = .block },
    .{ .x = 13, .z = -22, .yaw = 70, .s = 1.0, .kind = .block },
    .{ .x = -9, .z = -44, .yaw = 30, .s = 1.0, .kind = .block },
    .{ .x = 20, .z = -18, .yaw = 55, .s = 1.0, .kind = .block },
    .{ .x = -22, .z = -6, .yaw = -35, .s = 0.9, .kind = .block },
    // war banners flanking the avenue + a headless sentinel by the grace
    .{ .x = 7.5, .z = -11, .yaw = -18, .s = 1.0, .kind = .banner },
    .{ .x = -7.5, .z = -33, .yaw = 155, .s = 1.1, .kind = .banner },
    .{ .x = -8.5, .z = 7, .yaw = 155, .s = 1.0, .kind = .statue },
    // rubble scatter near the path
    .{ .x = 2.5, .z = -13, .yaw = 45, .s = 1.0, .kind = .rubble },
    .{ .x = -4, .z = -34, .yaw = 10, .s = 1.0, .kind = .rubble },
    .{ .x = 8, .z = 2, .yaw = 70, .s = 0.8, .kind = .rubble },
    .{ .x = -8, .z = -20, .yaw = 0, .s = 1.0, .kind = .rubble },
    // hand-placed flora accents: glowing blooms hug the grace; flowers among the graves
    .{ .x = 2.1, .z = 5.5, .yaw = 40, .s = 1.0, .kind = .glow },
    .{ .x = 4.2, .z = 7.6, .yaw = 210, .s = 0.85, .kind = .glow },
    .{ .x = -11.8, .z = -30.6, .yaw = 75, .s = 1.0, .kind = .flowers },
    .{ .x = 12.4, .z = -27.2, .yaw = 150, .s = 0.9, .kind = .flowers },
    .{ .x = -13.2, .z = -15.7, .yaw = 25, .s = 1.15, .kind = .reeds },
    // denser flowers ringing the graveyard — mourning blooms clustered on the graves
    .{ .x = -9.6, .z = -28.2, .yaw = 20, .s = 0.95, .kind = .flowers },
    .{ .x = -13.5, .z = -27.8, .yaw = 130, .s = 1.05, .kind = .flowers },
    .{ .x = -15.4, .z = -31.4, .yaw = 250, .s = 0.9, .kind = .flowers },
    .{ .x = -12.2, .z = -34.4, .yaw = 300, .s = 1.0, .kind = .flowers },
    .{ .x = -9.4, .z = -32.6, .yaw = 60, .s = 0.85, .kind = .flowers },
    .{ .x = 11.0, .z = -24.2, .yaw = 200, .s = 0.9, .kind = .flowers },
    .{ .x = 14.6, .z = -24.8, .yaw = 20, .s = 0.95, .kind = .flowers },
    // a brazier at the arch, so the threshold reads at dusk and the piers catch firelight
    .{ .x = -3.5, .z = -30.2, .yaw = 0, .s = 1.0, .kind = .brazier },
    // the paving of the old road surfacing through the grass
    .{ .x = 0, .z = -4, .yaw = 0, .s = 1.2, .kind = .paving },
    .{ .x = 0.6, .z = -19, .yaw = 40, .s = 1.1, .kind = .paving },
    .{ .x = -0.8, .z = -38, .yaw = 15, .s = 1.0, .kind = .paving },
};

fn avenue(p: *Placer) void {
    for (avenue_layout) |q| p.at(q.kind, q.x, q.z, q.yaw, q.s);
    // The start's own dressing, off the table because it is placed RELATIVE to what's already
    // there: ivy at the feet of the columns, lanterns marking the way north, and the meadow the
    // hero actually stands in. The runway (|x| < 3.4) stays clear — `belt` enforces that.
    ivyOnRuins(p, -30, -46, 30, 26);
    p.at(.lantern, 4.6, 1.5, 0, 1.0);
    p.at(.lantern, -4.6, -22.0, 0, 1.0);
    p.at(.well, -13.5, 3.0, 0, 1.0);
    p.at(.shrine, 6.8, -3.5, 200, 1.0);
    p.at(.cairn, -5.2, 18.0, 0, 1.1);
    p.at(.barrels, 9.5, -16.0, 50, 0.95);
    // A dense flowering meadow around the grace — the first thing the player ever looks at.
    p.belt(.wildflowers, -18, -6, 18, 24, 60, 0.85, 1.35);
    p.belt(.grasstall, -20, -8, 20, 26, 80, 0.85, 1.4);
    p.belt(.clover, -20, -8, 20, 26, 60, 0.9, 1.5);
    p.belt(.foxglove, -18, -6, 18, 22, 26, 0.85, 1.2);
    p.belt(.sapling, -24, -42, 24, 26, 30, 0.8, 1.2);
    p.belt(.thicket, -26, -44, 26, 26, 20, 0.85, 1.25);
    p.belt(.bush, -26, -44, 26, 26, 34, 0.85, 1.3);
    p.belt(.mushrooms, -22, -40, 22, 24, 24, 0.9, 1.3);
    p.belt(.rocks, -26, -44, 26, 26, 22, 0.8, 1.2);
    p.belt(.outcrop, -28, -44, 28, 26, 10, 0.85, 1.2);
}

// ── NORTH: THE FALLEN CITY ─────────────────────────────────────────────────────────────
// What the avenue was pointing at all along. A processional way runs on north to a plaza; the
// perimeter wall is broken into runs; a chapel off the west side is roofed and torchlit, and
// two watchtowers still stand. The colossal horizon gate closes the view 120 m out.
fn fallenCity(p: *Placer) void {
    // The processional way carries on: colonnade every 11 m, alternating whole and snapped,
    // with paving and rubble underfoot.
    var z: f32 = -48;
    while (z > -112) : (z -= 11) {
        const wob = p.rng.signed() * 1.2;
        for ([_]f32{ -6.5, 6.5 }) |side| {
            const kind: Kind = if (p.rng.float() < 0.45) .pillar else .broken;
            p.at(kind, side + wob, z + p.rng.signed() * 1.5, p.rng.range(-14, 14), p.rng.range(0.85, 1.15));
        }
        if (p.rng.float() < 0.6) p.jit(.paving, p.rng.range(-3.2, 3.2), z, 2.5, 0.9, 1.4);
        if (p.rng.float() < 0.5) p.jit(.rubble, p.rng.range(-5, 5), z, 3.0, 0.8, 1.3);
    }
    // The PLAZA at (0, -80): a paved floor, a sentinel statue on each side, braziers, and the
    // stumps of a colonnade that ringed it.
    var i: i32 = 0;
    while (i < 14) : (i += 1) p.jit(.paving, 0, -80, 13.0, 1.0, 1.5);
    p.at(.statue, -9.5, -74, 150, 1.25);
    p.at(.statue, 9.0, -86, 20, 1.15);
    p.at(.brazier, -5.0, -79.0, 0, 1.1);
    p.at(.brazier, 5.4, -81.5, 0, 1.0);
    p.ring(.broken, 0, -80, 15.5, 12, 5, 0.8, 1.2);
    p.at(.monolith, 0, -80, p.rng.range(0, 360), 1.35); // a broken victory stone at the centre
    p.belt(.rubble, -18, -94, 18, -66, 16, 0.8, 1.4);

    // THE CHAPEL — roofed over its altar end, so the inside is genuinely dark. Four standing
    // torches set against the walls are what make it readable, and the doorway faces the
    // processional way (yaw 90 turns its local −Z door to face world −X… so use yaw 270 to
    // open EAST, toward the road).
    const cx: f32 = -30.0;
    const cz: f32 = -66.0;
    p.at(.chapel, cx, cz, 270, 1.0);
    // Torch positions in the chapel's LOCAL frame, then rotated by that same yaw. THREE, not one
    // per corner: with a 6 m radius each, three read as three pools of light with shadow between
    // them, where four filled the nave evenly and there was nothing left to light.
    const torches = [_][2]f32{ .{ -1.9, 2.4 }, .{ 1.9, 2.4 }, .{ 1.9, -1.4 } };
    for (torches) |t| {
        const w = localToWorld(t[0], t[1], 270, 1.0);
        p.at(.torch, cx + w[0], cz + w[1], p.rng.range(0, 360), 0.95);
    }
    p.at(.brazier, cx + 5.2, cz + 0.6, 0, 0.95); // one outside the door, marking it from the road
    p.belt(.graves, cx - 9, cz - 8, cx - 3, cz + 8, 5, 0.85, 1.15);
    p.belt(.rubble, cx - 7, cz - 9, cx + 7, cz + 9, 7, 0.8, 1.2);
    p.belt(.flowers, cx - 9, cz - 9, cx - 2, cz + 9, 8, 0.8, 1.1);

    // Two WATCHTOWERS, each with a torch burning in its dark ground room.
    towerSite(p, 36.0, -88.0, 20);
    towerSite(p, -52.0, -104.0, 200);

    // The perimeter: broken wall runs on three sides of the city, laid end to end with gaps.
    wallRun(p, -46, -120, 46, -120, 7.4); // north face
    wallRun(p, -46, -120, -46, -58, 7.4); // west face
    wallRun(p, 46, -120, 46, -62, 7.4); // east face
    // A RUINED QUARTER either side of the way: the shells of houses, close-packed the way a
    // city is, so the place reads as somewhere people lived and not only as monuments.
    const quarter = [_][3]f32{
        .{ 20, -58, 84 },   .{ 27, -64, 12 },   .{ 19, -70, 96 },  .{ 28, -76, 4 },
        .{ -18, -92, 270 }, .{ -25, -99, 186 }, .{ -16, -105, 8 }, .{ 24, -100, 200 },
        .{ 31, -107, 92 },  .{ -30, -86, 96 },
    };
    for (quarter) |h| {
        p.at(.cottage, h[0], h[1], h[2] + p.rng.signed() * 8, p.rng.range(0.95, 1.35));
        p.belt(.rubble, h[0] - 5, h[1] - 5, h[0] + 5, h[1] + 5, 3, 0.8, 1.3);
        if (p.rng.float() < 0.45) p.jit(.paving, h[0], h[1] - 5.5, 2.0, 1.0, 1.4);
    }
    // Carts abandoned on the road out, and swords left where men fell.
    p.at(.cart, 4.6, -55.0, 28, 1.0);
    p.at(.cart, -5.8, -97.0, 200, 0.95);
    p.belt(.sword, -20, -110, 20, -50, 9, 0.85, 1.15);
    p.belt(.banner, -24, -112, 24, -52, 6, 0.9, 1.2);
    p.belt(.block, -40, -118, 40, -50, 26, 0.85, 1.35);
    p.belt(.tree, -42, -118, 42, -48, 16, 0.8, 1.25);
    // The city's own furniture: wells and lanterns on the road, stair fragments and tombs among
    // the ruins, ivy taking the walls, bones where the fighting was worst.
    p.at(.well, -12.0, -62.0, 0, 1.05);
    p.at(.well, 16.5, -95.0, 0, 1.0);
    p.at(.shrine, 5.5, -50.0, 186, 1.0);
    p.at(.gibbet, -8.5, -54.0, 200, 1.05);
    p.at(.gibbet, 11.0, -110.0, 20, 0.95);
    var ln: i32 = 0;
    while (ln < 8) : (ln += 1) { // lanterns down the processional way, alternating sides
        const lz = -52.0 - @as(f32, @floatFromInt(ln)) * 8.5;
        p.at(.lantern, if (@mod(ln, 2) == 0) @as(f32, 4.2) else -4.2, lz, 0, p.rng.range(0.9, 1.1));
    }
    p.belt(.stairs, -42, -116, 42, -50, 14, 0.85, 1.3);
    p.belt(.sarcophagus, -40, -114, 40, -52, 12, 0.9, 1.25);
    p.belt(.barrels, -38, -112, 38, -50, 18, 0.85, 1.2);
    p.belt(.woodpile, -36, -110, 36, -52, 10, 0.85, 1.15);
    p.belt(.bones, -40, -116, 40, -48, 22, 0.85, 1.3);
    p.belt(.cart, -34, -112, 34, -50, 8, 0.85, 1.1);
    p.belt(.fence, -38, -112, 38, -52, 14, 0.9, 1.2);
    ivyOnRuins(p, -46, -122, 46, -46); // creeper taking the ruins back — only ON the stone
    p.belt(.nettles, -44, -120, 44, -48, 120, 0.85, 1.35); // …and nettles in every corner
    p.belt(.sapling, -44, -120, 44, -48, 70, 0.8, 1.2); // trees coming up through the streets
    p.belt(.thicket, -44, -120, 44, -48, 40, 0.85, 1.3);
    // The horizon giants, dissolved by haze — now genuinely far out, where the pulled-back
    // haze still reduces them to silhouettes.
    p.at(.gate, 2, -124, 4, 1.35);
    p.at(.tower, -34, -132, 10, 1.4);
    p.at(.tower, 44, -126, -25, 1.15);
    p.at(.tower, -96, -128, 40, 1.2);
    p.at(.tower, 104, -120, 15, 1.3);
    p.at(.tower, -128, -66, 55, 1.1);
    p.at(.tower, 132, -78, -30, 1.0);
}

// A watchtower and its dressing: a torch inside the dark room, a brazier at the door, spill.
fn towerSite(p: *Placer, x: f32, z: f32, yaw: f32) void {
    p.at(.watchtower, x, z, yaw, 1.0);
    p.at(.torch, x + p.rng.signed() * 0.9, z + p.rng.signed() * 0.9, p.rng.range(0, 360), 0.9); // inside the drum
    const door = localToWorld(0, -3.6, yaw, 1.0); // just outside the doorway (local −Z)
    p.at(.brazier, x + door[0], z + door[1], 0, 1.0);
    p.belt(.rubble, x - 6, z - 6, x + 6, z + 6, 5, 0.8, 1.3);
    p.belt(.block, x - 8, z - 8, x + 8, z + 8, 3, 0.8, 1.1);
}

// Sow ivy at the FEET of the stonework already standing inside a box. Ivy climbs: its runners only
// make sense with a wall behind them, so it is placed by walking the props that are there rather
// than by scattering over ground. Runs after the structures, before the flora scatter.
fn ivyOnRuins(p: *Placer, x0: f32, z0: f32, x1: f32, z1: f32) void {
    const n = p.e.nprops; // snapshot: the ivy we add must not seed more ivy
    for (p.e.props[0..n]) |pr| {
        switch (pr.kind) {
            .wall, .pillar, .broken, .block, .arch, .statue, .cottage, .chapel, .watchtower, .stairs, .monolith => {},
            else => continue,
        }
        if (pr.pos.x < x0 or pr.pos.x > x1 or pr.pos.z < z0 or pr.pos.z > z1) continue;
        if (p.rng.float() > 0.55) continue;
        const nfo = props.info(pr.kind);
        // Hug the base: just outside the prop's own footprint, so the runners lie against it.
        const a = p.rng.angle();
        const d = nfo.bound * pr.scale * p.rng.range(0.18, 0.42);
        p.at(.ivy, pr.pos.x + mathx.cosf(a) * d, pr.pos.z + mathx.sinf(a) * d, mathx.degrees(a), p.rng.range(0.85, 1.5));
    }
}

// A broken run of city wall from a→b: segments laid nose to tail with gaps where it fell.
fn wallRun(p: *Placer, ax: f32, az: f32, bx: f32, bz: f32, seg: f32) void {
    const dx = bx - ax;
    const dz = bz - az;
    const len = @sqrt(dx * dx + dz * dz);
    const ux = dx / len;
    const uz = dz / len;
    const yaw = mathx.degrees(std.math.atan2(-uz, ux)); // local +X is (cos yaw, −sin yaw)
    var t: f32 = seg * 0.5;
    while (t < len) : (t += seg * p.rng.range(1.0, 1.5)) {
        if (p.rng.float() < 0.22) continue; // a collapsed stretch
        const s = p.rng.range(0.9, 1.25);
        p.at(.wall, ax + ux * t + p.rng.signed() * 0.6, az + uz * t + p.rng.signed() * 0.6, yaw + p.rng.signed() * 6, s);
        if (p.rng.float() < 0.35) p.jit(.rubble, ax + ux * t, az + uz * t, 3.0, 0.8, 1.2);
    }
}

// A prop-local (x, z) offset carried through an instance's yaw + scale into world offsets.
// Same convention the colliders use: local +X → (cos, −sin), local +Z → (sin, cos).
fn localToWorld(lx: f32, lz: f32, yaw: f32, scale: f32) [2]f32 {
    const th = mathx.radians(yaw);
    const c = mathx.cosf(th);
    const s = mathx.sinf(th);
    return .{ scale * (lx * c + lz * s), scale * (-lx * s + lz * c) };
}

// ── EAST: THE TARN ─────────────────────────────────────────────────────────────────────
// A shallow peat lake you WADE (owner's call — there is no swim, and an invisible wall on open
// water feels worse than ankle-deep water). Drowned columns stand in it, a stone causeway runs
// out and stops where its middle span fell in, willows lean over the margin, reeds everywhere.
fn theTarn(p: *Placer) void {
    const lx: f32 = 104.0;
    const lz: f32 = 6.0;
    p.atY(.water, lx, 0, lz, 0, 3.1); // ~40 m across
    p.atY(.water, 62.0, 0.004, -52.0, 40, 1.05); // a separate pool to the north-west (offset Y:
    //   two coplanar water sheets would z-fight, and 4 mm is invisible)

    // The causeway: runs west→east out into the tarn, ending in its collapsed span. Scale 1.35
    // gives a 13.5 m crossing about 4 m wide — at 2.4 its flagstones were nearly 2 m each and
    // the whole thing read as a pier built for something much larger than the hero.
    p.at(.causeway, 74.0, 8.0, 6, 1.35);
    p.at(.causeway, 86.5, 9.4, 10, 1.35); // a second span carrying on out into deeper water
    p.belt(.rocks, 66, 0, 82, 16, 8, 0.8, 1.3);

    // Drowned ruin: columns and blocks standing in the shallows — placed INSIDE the sheet so
    // they rise through it, which is the whole read.
    var i: i32 = 0;
    while (i < 9) : (i += 1) {
        const a = p.rng.angle();
        const d = p.rng.range(6.0, 34.0);
        p.at(if (p.rng.float() < 0.6) .broken else .block, lx + mathx.cosf(a) * d, lz + mathx.sinf(a) * d, p.rng.range(0, 360), p.rng.range(0.8, 1.2));
    }
    // The margin: willows leaning over, reed beds in the shallows and out onto the wet ground.
    var w: i32 = 0;
    while (w < 11) : (w += 1) {
        const a = p.rng.angle();
        const d = p.rng.range(36.0, 46.0);
        p.at(.willow, lx + mathx.cosf(a) * d, lz + mathx.sinf(a) * d, p.rng.range(0, 360), p.rng.range(0.85, 1.3));
    }
    // The bed: reeds and bulrushes in a broad band straddling the shoreline, thickest right at it.
    var r: i32 = 0;
    while (r < 420) : (r += 1) {
        const a = p.rng.angle();
        const d = p.rng.range(26.0, 54.0);
        const kind: Kind = if (p.rng.float() < 0.45) .cattails else .reeds;
        p.at(kind, lx + mathx.cosf(a) * d, lz + mathx.sinf(a) * d, p.rng.range(0, 360), p.rng.range(0.9, 1.55));
    }
    // LILY PADS, floating — placed INSIDE the sheet, which the flora scatter is forbidden from
    // doing (it rejects open water), so they have to be hand-sown here.
    // Sown in RAFTS rather than evenly: lilies spread from a rootstock, so they come in patches
    // hugging the shallows, with open water between them.
    var raft: i32 = 0;
    while (raft < 14) : (raft += 1) {
        const ra = p.rng.angle();
        const rd = p.rng.range(16.0, 33.0); // out from the middle, toward the shallow rim
        const rx = lx + mathx.cosf(ra) * rd;
        const rz = lz + mathx.sinf(ra) * rd;
        var lp: i32 = 0;
        while (lp < 7) : (lp += 1) {
            const a = p.rng.angle();
            const d = p.rng.range(0.0, 4.5) * @sqrt(p.rng.float());
            p.at(.lilypads, rx + mathx.cosf(a) * d, rz + mathx.sinf(a) * d, p.rng.range(0, 360), p.rng.range(0.85, 1.6));
        }
    }
    var lp2: i32 = 0;
    while (lp2 < 14) : (lp2 += 1) {
        const a = p.rng.angle();
        const d = p.rng.range(1.0, 9.0);
        p.at(.lilypads, 62.0 + mathx.cosf(a) * d, -52.0 + mathx.sinf(a) * d, p.rng.range(0, 360), p.rng.range(0.8, 1.3));
    }
    p.belt(.boulder, 62, -40, 150, 55, 26, 0.8, 1.5);
    p.belt(.rocks, 58, -50, 152, 60, 44, 0.8, 1.4);
    p.belt(.bush, 60, -55, 152, 62, 60, 0.8, 1.3);
    p.belt(.thicket, 58, -58, 152, 62, 40, 0.85, 1.4);
    p.belt(.nettles, 56, -60, 152, 62, 70, 0.85, 1.3);
    p.belt(.reeds, 52, -66, 78, -34, 90, 0.9, 1.4); // the north-western pool's own bed
    p.belt(.cattails, 52, -66, 78, -34, 60, 0.9, 1.4);
    p.belt(.willow, 52, -62, 74, -40, 8, 0.8, 1.1);
    p.belt(.log, 62, -30, 148, 50, 14, 0.8, 1.2);
    p.belt(.outcrop, 60, -50, 150, 58, 16, 0.85, 1.3);
    p.belt(.sapling, 58, -55, 152, 60, 45, 0.8, 1.2);
    p.belt(.birch, 56, -56, 152, 60, 16, 0.8, 1.15); // birches like wet ground
    // A camp on the shore, long cold.
    p.at(.campfire, 88.0, 34.0, 0, 1.0);
    p.at(.log, 90.6, 35.4, 20, 1.0);
    p.at(.cart, 85.0, 37.5, 130, 0.9);
    p.at(.barrels, 86.6, 31.6, 70, 0.95);
    p.at(.fence, 91.0, 30.0, 24, 0.95);
    // A fisherman's shrine facing the water, and a lantern on the causeway's landward end.
    p.at(.shrine, 72.0, 14.0, 100, 1.0);
    p.at(.lantern, 68.5, 8.5, 0, 1.0);
    // A lone tower away across the water, for the eye to travel to.
    p.at(.tower, 146, 30, -40, 1.1);
    p.at(.monolith, 70, 42, p.rng.range(0, 360), 1.1);
}

// ── WEST: THE OLD WOOD ─────────────────────────────────────────────────────────────────
// Great trees, close enough that their canopies overlap and the ground beneath them goes dark.
// Ferns and brambles on the floor, boulders under the moss, a stone circle in a clearing, and
// a woodcutter's cottage whose campfire is still ringed.
fn oldWood(p: *Placer) void {
    // THE CANOPY. Density rises toward the west edge, so walking in feels like entering it. The
    // species are MIXED — great trees for mass, conifers for the skyline's punctuation, birches
    // for a colour you can pick out at distance, snags so not everything is alive.
    var i: i32 = 0;
    while (i < 260) : (i += 1) {
        const x = p.rng.range(-152, -54);
        const z = p.rng.range(-120, 130);
        // Thin out on the eastern margin — a hard tree line reads as a wall of scenery.
        const edge = mathx.smoothstep(-54, -84, x);
        if (p.rng.float() > 0.18 + 0.82 * edge) continue;
        if (nearClearing(x, z)) continue;
        const roll = p.rng.float();
        const kind: Kind = if (roll < 0.52) p.anyOf(&props.BIG_TREES) else if (roll < 0.72) .conifer else if (roll < 0.86) .birch else if (roll < 0.94) .snag else .tree;
        p.at(kind, x, z, p.rng.range(0, 360), p.rng.range(0.68, 1.24));
    }
    // The understorey: young trees and thickets between the big trunks. This is the layer that
    // turns a stand of trees into a WOOD — without it you see straight through to the far edge.
    p.belt(.sapling, -152, -125, -54, 132, 150, 0.8, 1.35);
    p.belt(.thicket, -152, -125, -54, 132, 110, 0.85, 1.45);
    p.belt(.stump, -150, -120, -56, 130, 60, 0.8, 1.3);
    p.belt(.log, -150, -120, -56, 130, 55, 0.8, 1.3);
    p.belt(.boulder, -152, -125, -56, 132, 46, 0.8, 1.6);
    p.belt(.rocks, -152, -125, -56, 132, 60, 0.8, 1.4);
    p.belt(.outcrop, -152, -125, -58, 132, 24, 0.85, 1.4);
    p.belt(.fern, -152, -125, -54, 132, 220, 0.8, 1.35);
    p.belt(.bramble, -152, -125, -54, 132, 150, 0.8, 1.4);
    p.belt(.bush, -152, -125, -52, 132, 130, 0.8, 1.4);
    p.belt(.mushrooms, -152, -125, -54, 132, 130, 0.85, 1.5);
    p.belt(.bracken, -152, -125, -54, 132, 120, 0.85, 1.4);
    p.belt(.moss, -152, -125, -54, 132, 140, 0.9, 1.6);
    p.belt(.nettles, -150, -120, -56, 130, 70, 0.85, 1.3);
    // A ring of mushrooms in the deep wood, and a cairn or two marking a path nobody walks.
    p.ring(.mushrooms, -120, 52, 3.2, 9, 4, 0.9, 1.4);
    p.belt(.cairn, -145, -110, -60, 120, 7, 0.9, 1.2);
    p.belt(.bones, -148, -118, -58, 128, 9, 0.85, 1.2);

    // THE STONE CIRCLE, in a clearing the trees keep out of (see nearClearing).
    p.ring(.monolith, -98, -16, 8.5, 9, 6, 0.9, 1.25);
    p.at(.monolith, -98, -16, 30, 0.7); // a small altar stone at the centre
    p.belt(.flowers, -106, -24, -90, -8, 12, 0.8, 1.2);
    p.belt(.glow, -104, -22, -92, -10, 5, 0.9, 1.2); // the faint blooms only grow here and at the grace
    p.at(.brazier, -93.0, -11.0, 0, 1.0);

    // THE WOODCUTTER'S COTTAGE — doorway facing local −Z, turned to open east onto the wood.
    const hx: f32 = -74.0;
    const hz: f32 = 30.0;
    p.at(.cottage, hx, hz, 270, 1.05);
    const door = localToWorld(0, -4.6, 270, 1.05);
    p.at(.campfire, hx + door[0], hz + door[1], 0, 1.1);
    p.at(.log, hx + 4.4, hz + 3.0, 70, 1.0);
    p.at(.stump, hx + 3.2, hz - 3.4, 0, 1.15); // the chopping block
    p.at(.cart, hx + 6.5, hz - 1.0, 190, 0.95);
    p.at(.torch, hx + 1.6, hz + 0.4, 0, 0.9); // one still burning inside the shell
    // The yard: a woodpile against the gable, a well, a fence run, and the tools left out.
    p.at(.woodpile, hx - 3.6, hz + 2.6, 12, 1.05);
    p.at(.well, hx + 7.5, hz + 4.5, 0, 1.0);
    p.at(.fence, hx + 2.0, hz + 8.0, 6, 1.1);
    p.at(.fence, hx + 9.5, hz + 8.6, -8, 1.0);
    p.at(.barrels, hx - 5.0, hz - 2.2, 40, 1.0);
    p.at(.lantern, hx + 4.2, hz - 4.6, 0, 1.0);
    p.belt(.log, hx - 6, hz - 6, hx + 8, hz + 8, 10, 0.85, 1.2);
    p.belt(.bramble, hx - 10, hz - 10, hx + 10, hz + 10, 14, 0.8, 1.2);
    p.belt(.wildflowers, hx - 9, hz - 9, hx + 9, hz + 9, 18, 0.85, 1.25);
    p.belt(.mushrooms, hx - 8, hz - 8, hx + 8, hz + 8, 10, 0.9, 1.3);
}

// Places the wood's canopy leaves alone: the stone circle's clearing and the cottage yard.
fn nearClearing(x: f32, z: f32) bool {
    return mathx.dist2XZ(v3(x, 0, z), v3(-98, 0, -16)) < 18.0 * 18.0 or
        mathx.dist2XZ(v3(x, 0, z), v3(-74, 0, 30)) < 15.0 * 15.0;
}

// ── SOUTH: THE WINDSWEPT DOWNS ─────────────────────────────────────────────────────────
// Open, dry and nearly empty: the region that makes the others feel dense. Lone trees leaning
// off the prevailing wind, field stones, old graves, and a watchtower on the rise.
fn theDowns(p: *Placer) void {
    // Kept the SPARSEST region on purpose — it is what makes the wood and the city feel dense —
    // but sparse means "few tall things", not "empty ground": the heath cover underfoot is thick.
    p.belt(.bigtree, -120, 52, 40, 150, 18, 0.7, 1.05);
    p.belt(.tree, -130, 48, 60, 152, 32, 0.8, 1.25);
    p.belt(.snag, -130, 50, 70, 150, 12, 0.8, 1.1);
    p.belt(.boulder, -140, 46, 140, 152, 40, 0.8, 1.7);
    p.belt(.rocks, -140, 46, 145, 154, 60, 0.8, 1.4);
    p.belt(.outcrop, -140, 46, 145, 152, 34, 0.85, 1.45);
    p.belt(.scree, -140, 48, 145, 152, 26, 0.85, 1.4);
    p.belt(.cairn, -120, 52, 120, 150, 16, 0.9, 1.25);
    p.belt(.graves, -60, 60, 60, 140, 20, 0.8, 1.2);
    p.belt(.sarcophagus, -50, 66, 50, 130, 7, 0.9, 1.2);
    p.belt(.monolith, -110, 60, 110, 148, 11, 0.9, 1.3);
    p.belt(.wall, -100, 58, 100, 145, 12, 0.9, 1.2);
    p.belt(.shrub, -145, 44, 145, 155, 90, 0.8, 1.4);
    p.belt(.gorse, -145, 44, 145, 155, 110, 0.85, 1.5);
    p.belt(.heather, -148, 44, 148, 156, 200, 0.9, 1.6);
    p.belt(.thistle, -140, 46, 140, 152, 90, 0.85, 1.3);
    p.belt(.sword, -40, 55, 40, 120, 9, 0.9, 1.1);
    p.belt(.bones, -80, 58, 80, 140, 12, 0.85, 1.25);
    towerSite(p, 22.0, 98.0, 350);
    p.at(.tower, -74, 138, 25, 1.0);
    p.at(.tower, 96, 132, -15, 1.15);
    // A lonely fire out on the downs — the one warm thing in the region.
    p.at(.campfire, -34.0, 74.0, 0, 1.0);
    p.at(.log, -32.0, 76.2, 30, 1.0);
    p.at(.cairn, -30.5, 71.0, 0, 1.15);
    // A gibbet on the road south, and a shrine further along it.
    p.at(.gibbet, 6.0, 62.0, 30, 1.0);
    p.at(.shrine, -4.5, 88.0, 186, 1.0);
    p.at(.lantern, 3.0, 104.0, 0, 1.0);
}

// ── THE EDGE: a cliff wall right round the world ────────────────────────────────────────
// The movement clamp sits just inside a rock face, so the world's edge reads as terrain rather
// than as an invisible wall in open grass. Each segment's detailed face is its local −Z, so
// each side takes the yaw that turns that face INWARD (north 180, south 0, east 90, west 270).
// Segment scale is a function of WHERE ALONG the wall it sits: two long sines (~90 m and ~37 m)
// plus a little noise. Purely random per-segment scale gives the crest hedge-trimmer jitter;
// summed long waves read as topography — headlands and saddles you see coming.
fn ridgeScale(p: *Placer, along: f32) f32 {
    return 1.03 + 0.20 * mathx.sinf(along * 0.070) + 0.10 * mathx.sinf(along * 0.170 + 1.9) + p.rng.signed() * 0.05;
}

fn cliffRing(p: *Placer) void {
    // Step 8 against a 10.4 m wide segment: they OVERLAP, which is what turns a row of separate
    // rocks into one continuous escarpment. Scale stays inside 0.92..1.24 for the same reason —
    // at the old 0.85..1.45 the crest line jumped 8 m between neighbours and sawtoothed.
    const step: f32 = 6.5; // deep overlap: see the cliff mesh's note on notches between segments
    var t: f32 = -CLIFF_EDGE;
    while (t <= CLIFF_EDGE) : (t += step) {
        const jitter = p.rng.signed() * 1.6;
        // North (−Z) and south (+Z) faces, then east (+X) and west (−X): each side gets the yaw
        // that turns the segment's detailed local −Z face INWARD, and a variant picked at random.
        // Height comes from ridgeScale — see there for why it isn't just rng.
        p.at(p.anyOf(&props.CLIFFS), t + jitter, -CLIFF_EDGE - p.rng.range(0, 2.5), 180 + p.rng.signed() * 7, ridgeScale(p, t));
        p.at(p.anyOf(&props.CLIFFS), t - jitter, CLIFF_EDGE + p.rng.range(0, 2.5), 0 + p.rng.signed() * 7, ridgeScale(p, t + 91));
        p.at(p.anyOf(&props.CLIFFS), CLIFF_EDGE + p.rng.range(0, 2.5), t + jitter, 90 + p.rng.signed() * 7, ridgeScale(p, t + 213));
        p.at(p.anyOf(&props.CLIFFS), -CLIFF_EDGE - p.rng.range(0, 2.5), t - jitter, 270 + p.rng.signed() * 7, ridgeScale(p, t + 347));
    }
    // Talus and scrub spilling off the feet of the walls, so the base isn't a clean line. Kept
    // INSIDE HALF-4: the cliff mesh has its own talus reaching ~4 m in, and a boulder dropped
    // into that shows as a wrong-coloured lump growing out of the rock.
    var i: i32 = 0;
    while (i < 90) : (i += 1) {
        const along = p.rng.range(-CLIFF_EDGE, CLIFF_EDGE);
        const off = p.rng.range(HALF - 20, HALF - 4);
        const side = p.rng.intn(4);
        const pos: [2]f32 = switch (side) {
            0 => .{ along, -off },
            1 => .{ along, off },
            2 => .{ off, along },
            else => .{ -off, along },
        };
        const kind: Kind = if (p.rng.float() < 0.45) .boulder else if (p.rng.float() < 0.7) .rocks else .bush;
        p.at(kind, pos[0], pos[1], p.rng.range(0, 360), p.rng.range(0.8, 1.5));
    }
}

// ── the seeded ground cover ────────────────────────────────────────────────────────────
// A stratified scatter over the whole world: one candidate per LATTICE cell at a jittered
// position, so coverage is even without the O(n·m) rejection sampling the small world used.
// Kind follows the region; DENSITY follows the region times the cover FIELD below.
// Lattice pitch: ONE candidate per cell of this size, jittered inside it.
const LATTICE: f32 = 3.3;

// ── THE COVER FIELD (owner's law: vary the density, a lot) ─────────────────────────────
// A per-region density CONSTANT gives every square metre the same cover, and the result is a
// carpet: uniformly thick, nowhere to walk, nothing to notice. Real ground has clearings you
// can see across and thickets you go round, and that difference is what makes a plain read as
// a place rather than as a texture.
//
// So the region number is the PEAK and this field scales it: two octaves of value noise (~34 m
// clearings-and-copses, broken up at ~11 m) pushed toward the extremes so it spends its time
// near 0 or near 1 instead of pooling in the middle. Mean ~0.62, which is also the overall
// thin-out. The SAME field drives the structure belts, so a clearing is a clearing for
// everything standing in it.
fn hash2(ix: i32, iz: i32) f32 {
    var h: u32 = @bitCast(ix *% 374761393 +% iz *% 668265263);
    h = (h ^ (h >> 13)) *% 1274126177;
    h ^= h >> 16;
    return @as(f32, @floatFromInt(h)) / 4294967295.0;
}

fn vnoise2(x: f32, z: f32) f32 {
    const fx = @floor(x);
    const fz = @floor(z);
    const ix: i32 = @intFromFloat(fx);
    const iz: i32 = @intFromFloat(fz);
    const tx = x - fx;
    const tz = z - fz;
    const ux = tx * tx * (3.0 - 2.0 * tx);
    const uz = tz * tz * (3.0 - 2.0 * tz);
    const a = hash2(ix, iz);
    const b = hash2(ix + 1, iz);
    const c = hash2(ix, iz + 1);
    const d = hash2(ix + 1, iz + 1);
    const lo = a + (b - a) * ux;
    return lo + ((c + (d - c) * ux) - lo) * uz;
}

pub fn coverField(x: f32, z: f32) f32 {
    const big = vnoise2(x / 34.0, z / 34.0);
    const fine = vnoise2(x / 11.0 + 31.7, z / 11.0 - 12.3);
    const t = mathx.clampF((big * 0.72 + fine * 0.28 - 0.18) / 0.64, 0, 1);
    return t * t * (3.0 - 2.0 * t) * 1.25;
}

fn scatterFlora(p: *Placer) void {
    var buf: [MAX_NEAR]collision.Solid = undefined;
    const n: i32 = @intFromFloat(@ceil(2 * HALF / LATTICE));
    var iz: i32 = 0;
    while (iz < n) : (iz += 1) {
        var ix: i32 = 0;
        while (ix < n) : (ix += 1) {
            const bx = -HALF + (@as(f32, @floatFromInt(ix)) + 0.5) * LATTICE;
            const bz = -HALF + (@as(f32, @floatFromInt(iz)) + 0.5) * LATTICE;
            const x = bx + p.rng.signed() * LATTICE * 0.48;
            const z = bz + p.rng.signed() * LATTICE * 0.48;
            const r = region(x, z);
            if (p.rng.float() > r.density * coverField(x, z)) continue;
            if (onRunway(x, z)) continue;
            if (p.e.inWater(x, z, 0.97)) continue; // reeds may stand at the rim, nothing mid-lake
            // Don't grow through the world: the solid grid already knows what is here.
            const probe = v3(x, 0.2, z);
            if (collision.blockedBy(probe, 0.35, p.e.nearSolids(probe, 1.4, &buf))) continue;
            p.at(r.pick(&p.rng), x, z, p.rng.range(0, 360), p.rng.range(0.72, 1.38));
        }
    }
}

// A region's ground-cover character: what it grows, and how much of the lattice it fills WHERE
// IT IS THICKEST — `density` is the peak, not the average; `coverField` scales it down from
// there, to nothing in the clearings.
const Region = struct {
    density: f32,
    kinds: []const Kind,

    fn pick(self: Region, rng: *mathx.Rng) Kind {
        return self.kinds[@intCast(rng.intn(@intCast(self.kinds.len)))];
    }
};

// Weighted by REPETITION in the list — the cheapest honest way to weight a small set, and it
// keeps each region's mix readable as a line of text. Each list should hold at least one LOW
// ground-hugger (clover / moss / heather): without something filling between the standing plants
// you get an even spacing of individuals with bare soil showing through, which reads as sparse no
// matter how many you place.
const COVER_PLAIN = [_]Kind{
    .grasstall, .grasstall, .grasstall, .patch,  .patch,       .tuft,
    .clover,    .clover,    .moss,      .shrub,  .wildflowers, .wildflowers,
    .flowers,   .thistle,   .foxglove,  .bracken,
};
const COVER_WOOD = [_]Kind{
    .fern,   .fern,      .fern,   .bramble, .bramble,   .thicket,
    .bush,   .moss,      .moss,   .moss,    .mushrooms, .mushrooms,
    .bracken, .bracken,  .clover, .nettles, .grasstall, .patch,
};
const COVER_MARSH = [_]Kind{
    .reeds,  .reeds,      .cattails, .cattails, .cattails, .patch,
    .bush,   .nettles,    .moss,     .moss,     .grasstall, .wildflowers,
};
// NB no ivy in the city's general cover, even though it belongs to the city: ivy is a CLIMBER, and
// dropped on open ground its runners stand up unsupported like beanstalks. It only goes where there
// is stone to take it — see ivyOnRuins.
const COVER_CITY = [_]Kind{
    .tuft,   .tuft, .patch, .nettles, .nettles,     .thistle,
    .clover, .moss, .shrub, .shrub,   .wildflowers, .grasstall,
};
const COVER_DOWNS = [_]Kind{
    .heather, .heather, .heather, .gorse, .gorse,   .patch,
    .patch,   .tuft,    .tuft,    .moss,  .thistle, .bracken,
};

fn region(x: f32, z: f32) Region {
    if (x < -52) return .{ .density = 0.98, .kinds = &COVER_WOOD }; // thickets under the great trees
    if (x > 50) return .{ .density = 0.86, .kinds = &COVER_MARSH }; // reed beds, and open silt between
    if (z < -46) return .{ .density = 0.44, .kinds = &COVER_CITY }; // paved, trodden, sparse
    if (z > 46) return .{ .density = 0.58, .kinds = &COVER_DOWNS }; // wind-scoured
    return .{ .density = 0.80, .kinds = &COVER_PLAIN }; // the home plain, as it always was
}

// ── the indexes ────────────────────────────────────────────────────────────────────────

// Footprint colliders for every solid prop: each kind's local Part list, rotated by the
// instance yaw and scaled. Each solid carries its part's own TOP height, so arrows thunk into
// a chapel wall but arc clean over a causeway kerb.
fn buildSolids(e: *Env) void {
    for (e.props[0..e.nprops]) |pr| {
        const nfo = props.info(pr.kind);
        const s = pr.scale;
        const th = mathx.radians(pr.yaw);
        const c = mathx.cosf(th);
        const sn = mathx.sinf(th);
        for (nfo.parts) |part| {
            if (e.nsolids >= MAX_SOLIDS) @panic("env: MAX_SOLIDS exceeded — raise the cap");
            var sol = collision.capsule(
                pr.pos.x + s * (part.ax * c + part.az * sn),
                pr.pos.z + s * (-part.ax * sn + part.az * c),
                pr.pos.x + s * (part.bx * c + part.bz * sn),
                pr.pos.z + s * (-part.bx * sn + part.bz * c),
                part.r * s,
            );
            sol.h = part.h * s;
            e.solid_buf[e.nsolids] = sol;
            e.nsolids += 1;
        }
    }
    // CSR over the cells each solid's footprint touches (counting sort, two passes).
    var counts = [_]u32{0} ** NCELL;
    for (e.solid_buf[0..e.nsolids]) |s| {
        var it = SolidCells.init(s);
        while (it.next()) |c| counts[c] += 1;
    }
    var total: u32 = 0;
    for (counts, 0..) |n, i| {
        e.sgrid_start[i] = total;
        total += n;
    }
    e.sgrid_start[NCELL] = total;
    if (total > MAX_SOLID_REFS) @panic("env: MAX_SOLID_REFS exceeded — raise the cap");
    var cursor = e.sgrid_start;
    for (e.solid_buf[0..e.nsolids], 0..) |s, si| {
        var it = SolidCells.init(s);
        while (it.next()) |c| {
            e.sgrid_items[cursor[c]] = @intCast(si);
            cursor[c] += 1;
        }
    }
}

// The cells a solid's expanded footprint covers. Insertion by BBOX (not just the centre) is
// what makes nearSolids exact-enough: a query can then never miss a solid it overlaps.
const SolidCells = struct {
    x0: usize,
    x1: usize,
    z0: usize,
    z1: usize,
    cx: usize,
    cz: usize,

    fn init(s: collision.Solid) SolidCells {
        const x0 = cellCoord(@min(s.a.x, s.b.x) - s.r);
        const z0 = cellCoord(@min(s.a.z, s.b.z) - s.r);
        return .{
            .x0 = x0,
            .x1 = cellCoord(@max(s.a.x, s.b.x) + s.r),
            .z0 = z0,
            .z1 = cellCoord(@max(s.a.z, s.b.z) + s.r),
            .cx = x0,
            .cz = z0,
        };
    }

    fn next(self: *SolidCells) ?usize {
        if (self.cz > self.z1) return null;
        const out = self.cz * GRID_N + self.cx;
        self.cx += 1;
        if (self.cx > self.x1) {
            self.cx = self.x0;
            self.cz += 1;
        }
        return out;
    }
};

// Bucket every prop into its cell, twice: once into the structure index, once into the flora
// index. Same counting-sort shape as the solid grid.
fn indexProps(e: *Env) void {
    fillIndex(e, &e.stx, false);
    fillIndex(e, &e.flx, true);
}

fn fillIndex(e: *Env, idx: *Index, want_flora: bool) void {
    // ZERO the per-cell maxima before accumulating them. They are `max`-folded below, so they must
    // start low — and they do NOT arrive zeroed: Env is built IN PLACE inside a Game that came from
    // `alloc.create`, so `Index`'s struct-literal defaults never run and these three arrays are raw
    // heap bytes. Reading them is illegal behaviour whatever those bytes happen to be — but MEASURED,
    // a ReleaseFast build without these three lines still culled to the same 985 draws / 204 cells, so
    // the garbage it was handed folded away harmlessly. That is luck, not correctness: a garbage-HIGH
    // view/bound makes the per-cell reject always pass, silently disabling the first and cheapest
    // culling stage (and inflating the Stats overlay's `cells`), and nothing about the allocator
    // guarantees it keeps being lucky. Empty cells are safe either way — drawIndexed skips them
    // before it reads any maximum.
    idx.bound = [_]f32{0} ** NCELL;
    idx.view = [_]f32{0} ** NCELL;
    idx.top = [_]f32{0} ** NCELL;
    var counts = [_]u32{0} ** NCELL;
    for (e.props[0..e.nprops]) |pr| {
        if (props.info(pr.kind).flora != want_flora) continue;
        counts[cellOf(pr.pos.x, pr.pos.z)] += 1;
    }
    var total: u32 = 0;
    for (counts, 0..) |n, i| {
        idx.start[i] = total;
        total += n;
    }
    idx.start[NCELL] = total;
    var cursor = idx.start;
    for (e.props[0..e.nprops], 0..) |pr, pi| {
        const nfo = props.info(pr.kind);
        if (nfo.flora != want_flora) continue;
        const c = cellOf(pr.pos.x, pr.pos.z);
        idx.items[cursor[c]] = @intCast(pi);
        cursor[c] += 1;
        idx.bound[c] = mathx.maxF(idx.bound[c], nfo.bound * pr.scale);
        idx.view[c] = mathx.maxF(idx.view[c], nfo.view);
        idx.top[c] = mathx.maxF(idx.top[c], nfo.top * pr.scale);
    }
}

// ── tests ──────────────────────────────────────────────────────────────────────────────
// These cover the pure geometry — the culler and the grid — which is where a silent mistake
// costs the most (a prop that vanishes on screen, or a wall you walk through). They need no
// GPU, so they run under `zig build test`.

fn viewLooking(eye: rl.Vector3, at: rl.Vector3) View {
    return View.fromCamera(.{
        .position = eye,
        .target = at,
        .up = v3(0, 1, 0),
        .fovy = 45,
        .projection = .perspective,
    }, 1.6);
}

test "the view culler keeps what is ahead and rejects what is behind or wide" {
    // EVERY orientation, because the first version of fromCamera assumed a handedness for the
    // camera basis, was right for the pencil-and-paper case and inverted for the real one — and
    // an inverted culler draws an EMPTY WORLD. A test that only checks one heading cannot see
    // that: the +Z case below is precisely the one that used to pass while the game was blank.
    const headings = [_]rl.Vector3{
        v3(0, 0, 1), v3(0, 0, -1), v3(1, 0, 0), v3(-1, 0, 0), // the four cardinals
        v3(0.7, -0.25, 0.7), v3(-0.6, -0.3, 0.74), // pitched down, like the real over-shoulder rig
        v3(0.1, -0.97, 0.1), // near-straight-down, like the top-down attack shot
    };
    for (headings) |h| {
        const eye = v3(3, 2, -4); // deliberately not the origin
        const vw = viewLooking(eye, mathx.addV(eye, h));
        const ahead = mathx.addV(eye, mathx.scaleV(h, 20));
        const behind = mathx.addV(eye, mathx.scaleV(h, -20));
        try std.testing.expect(vw.visible(ahead, 0.5, 100)); // dead ahead
        try std.testing.expect(!vw.visible(behind, 0.5, 100)); // straight behind
        try std.testing.expect(!vw.visible(ahead, 0.5, 5)); // ahead but past the view distance
        try std.testing.expect(vw.visible(ahead, 0.5, 250)); // …same prop, longer view distance
        // A colossus centred outside the frustum still has geometry inside it — the case a
        // naive centre-point test drops, which shows as a cliff face popping at the screen edge.
        const wide = mathx.addV(ahead, mathx.scaleV(mathx.normV(cross(h, v3(0, 1, 0))), 30));
        try std.testing.expect(!vw.visible(wide, 0.5, 100));
        try std.testing.expect(vw.visible(wide, 26.0, 100));
    }
}

test "the culler accepts the full width of the screen, not just the axis" {
    // A prop out at the horizontal edge of a 16:10 45-deg-vertical frustum must survive: too
    // tight a horizontal angle silently thins the sides of every frame.
    const vw = viewLooking(v3(0, 0, 0), v3(0, 0, 1));
    const hf = std.math.atan(@tan(mathx.radians(45.0) * 0.5) * 1.6);
    const edge = v3(@tan(hf * 0.94) * 40.0, 0, 40); // 94% of the way to the edge, dead centre vertically
    try std.testing.expect(vw.visible(edge, 0.0, 100));
    try std.testing.expect(vw.visible(v3(-edge.x, 0, edge.z), 0.0, 100)); // …and the other side
}

test "the shadow cull keeps a distant TALL caster whose shadow still reaches the box" {
    const focus = v3(0, 0, 0);
    // Distances are DERIVED from SHADOW_BOX, not literals: this test used to say "60 m out" back
    // when SHADOW_ORTHO was 44 (box half-diagonal ~31 m). At the current 108 the half-diagonal is
    // ~76 m, so 60 m is comfortably INSIDE the box and even a grass tuft there casts into it —
    // the literal quietly stopped describing "outside the box" and the assertion inverted. Anchor
    // it to the box so retuning SHADOW_ORTHO can never strand it again.
    const outside = SHADOW_BOX + 10.0; // just beyond the box's own corner
    // A 15 m cliff out there is outside the box, but at this sun elevation its shadow travels
    // ~23 m — plus its own bulk, that reaches in. Dropping it (which a plain distance cull
    // would) deletes a real shadow from the frame.
    try std.testing.expect(castsInto(focus, v3(outside, 0, 0), 18.0, 15.5));
    // A grass-height prop the same distance out cannot possibly reach.
    try std.testing.expect(!castsInto(focus, v3(outside, 0, 0), 0.9, 0.8));
    // …and a tall one far enough out is genuinely irrelevant.
    try std.testing.expect(!castsInto(focus, v3(SHADOW_BOX + 60.0, 0, 0), 18.0, 15.5));
    // The sanity floor the whole cull rests on: anything INSIDE the box casts, whatever its size.
    try std.testing.expect(castsInto(focus, v3(SHADOW_BOX - 10.0, 0, 0), 0.2, 0.2));
}

test "grid cells round-trip a world position" {
    try std.testing.expectEqual(cellOf(0, 0), cellOf(1, 1)); // same cell, CELL is 16
    const c = cellOf(-100, 55);
    const centre = cellCentre(c);
    try std.testing.expect(@abs(centre.x - (-100)) <= CELL * 0.5);
    try std.testing.expect(@abs(centre.z - 55) <= CELL * 0.5);
    // Out-of-grid positions clamp into the edge cell instead of indexing off the end.
    try std.testing.expect(cellOf(-9999, 9999) < NCELL);
    try std.testing.expect(cellOf(9999, -9999) < NCELL);
}

test "a solid's cell iterator covers its whole footprint" {
    // A cliff-sized capsule spanning a cell boundary must be inserted into every cell it
    // touches, or a query from the neighbouring cell misses it and you walk through rock.
    var s = collision.capsule(-9, 0, 9, 0, 3);
    s.h = 15;
    var seen: usize = 0;
    var it = SolidCells.init(s);
    var hasLeft = false;
    var hasRight = false;
    while (it.next()) |c| {
        seen += 1;
        if (c == cellOf(-11, 0)) hasLeft = true;
        if (c == cellOf(11, 0)) hasRight = true;
    }
    try std.testing.expect(seen >= 2);
    try std.testing.expect(hasLeft and hasRight);
}

test "the cover field actually varies — real clearings and real thickets" {
    // The point of the field is VARIANCE. A field that never dips near zero has no clearings in
    // it and a field that never reaches its peak has no thickets, and either way the world goes
    // back to being one uniform carpet — which is the exact thing this replaced.
    var lo: f32 = 9;
    var hi: f32 = -9;
    var sum: f32 = 0;
    var n: f32 = 0;
    var x: f32 = -HALF;
    while (x <= HALF) : (x += 3) {
        var z: f32 = -HALF;
        while (z <= HALF) : (z += 3) {
            const f = coverField(x, z);
            lo = @min(lo, f);
            hi = @max(hi, f);
            sum += f;
            n += 1;
        }
    }
    try std.testing.expect(lo <= 0.02); // somewhere is bare
    try std.testing.expect(hi >= 1.15); // somewhere is choked
    const mean = sum / n;
    try std.testing.expect(mean > 0.45 and mean < 0.80); // …and it is not secretly a constant
}

test "the world's regions cover every reachable position with real ground cover" {
    // Every point inside the playable bounds must resolve to a region with a non-empty mix and
    // a plausible density — a gap here is a bald patch of terrain the player can walk to.
    var x: f32 = -HALF;
    while (x <= HALF) : (x += 7) {
        var z: f32 = -HALF;
        while (z <= HALF) : (z += 7) {
            const r = region(x, z);
            try std.testing.expect(r.kinds.len > 0);
            try std.testing.expect(r.density > 0.1 and r.density <= 1.0);
            for (r.kinds) |k| try std.testing.expect(props.info(k).flora);
        }
    }
}

test "the cliff ring stands outside the movement clamp" {
    // PLAY_HALF (game.zig) insets HALF by 2; the rock must be beyond that or the player is
    // stopped by air with the cliff still ahead of them.
    try std.testing.expect(CLIFF_EDGE > HALF);
    // …and inside the grid, or its cells clamp together and the culling degrades.
    try std.testing.expect(CLIFF_EDGE + props.info(.cliff).bound < GRID_HALF + CELL);
}
