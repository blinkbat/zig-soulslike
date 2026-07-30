const std = @import("std");
const rl = @import("raylib");
const gfx = @import("gfx.zig");
const mathx = @import("mathx.zig");
const collision = @import("collision.zig");
const props = @import("props.zig");
const wf = @import("worldfmt.zig");

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
// The world itself is DATA — `worlds/*.world`, an ordered list of authoring ops (worldfmt.zig)
// that `materialize` replays into the prop list below. This file no longer authors anything; it
// loads, indexes, culls and draws.
//
// All static and deterministic — every scatter runs off ITS OWN seeded mathx.Rng (one per op,
// not one per world), so the world is identical every launch, --shot stays comparable frame to
// frame, and editing one scatter cannot re-roll its neighbours.

// THE WORLD'S SIZE IS THE MAP'S (`wf.Map.half`), not a constant in here. It used to be both, and
// the copy in this file was the one that counted: the movement clamp read it, so a map could
// declare any `half:` it liked and the hero still stopped at 158 with the cliffs visibly further
// out. The only compile-time size left is the CEILING the fixed grid can index.
/// How far outside the playable bounds the rock wall stands.
pub const RIM_OUT: f32 = 6.0;
/// How far INSIDE the map's half the movement clamp sits, so the hero stops just short of the
/// rock rather than clipping into it. `game.playHalf` is the map's half less this.
pub const PLAY_INSET: f32 = 2.0;
/// The largest `half` the uniform grid can index without cells clamping together. Beyond this the
/// culling still WORKS but degrades — everything past the edge piles into the boundary cells, and a
/// cell that can't be rejected is thirty props tested individually. Derived, so raising GRID_N
/// raises this and the assertions below re-check themselves.
pub const MAX_HALF: f32 = GRID_HALF + CELL - RIM_OUT - CLIFF_BOUND;
/// The cliff mesh's own bounding radius, which sticks out past the rim it is placed on.
const CLIFF_BOUND: f32 = 18.0;
// The ground QUAD extends far past the bounds so the terrain runs all the way into full
// distance haze — no visible plane edge / sky band below the horizon, from anywhere. It has to
// clear the FARTHEST the player can stand plus the distance at which haze goes fully opaque
// (~1/HAZE_DENSITY x 3), or the plane's edge shows at the world's corners. One quad: free.
const GROUND_HALF: f32 = wf.DEFAULT_HALF + 220.0;

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
// 40 cells a side — 640 m, which covers a 280 m map's cliff ring (286 + 18 of cliff bound) with
// room over. Grown from 24 with the world; the arrays are BSS and the per-frame cost is one loop
// over NCELL doing four plane tests, so 1,600 cells instead of 576 is not measurable next to the
// prop work it saves. See MAX_HALF — that is the number this choice really sets.
const GRID_N: usize = 40;
const GRID_SPAN: f32 = CELL * @as(f32, @floatFromInt(GRID_N));
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

// How far away a fire's pool of light still reads at all. Kept at the OLD accept distance so the
// frustum cull in `uploadLights` changes only WHICH lights are dropped (the off-screen ones),
// never how far a visible one reaches.
const LIGHT_REACH: f32 = 90.0;

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

// `op` is the map op that placed this instance. It is what lets the editor turn a click on a
// rock into the line that grew it — without it, selection could only ever reach literals, and
// the generators (which are most of the world) would be unreachable except through the list.
const Prop = struct { kind: Kind, pos: rl.Vector3, yaw: f32, scale: f32, op: u16 = 0 };

/// The floor of the cover field's gate: a scatter that respects the field still places this
/// fraction of its attempts in a total clearing, so a clearing THINS the structures standing in
/// it without emptying it. Named because belt and disc both read it and a drift between the two
/// would be invisible in the world.
const FIELD_FLOOR: f32 = 0.35;

/// The ground plane's height, for anything that has to draw ON it (the editor's gizmos).
pub fn groundY() f32 {
    return GROUND_Y;
}

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
    // The scene this world draws through, kept so the painted soil can be pushed to its shader
    // without threading a Scene pointer through every editor call that touches the map.
    scene: ?*gfx.Scene = null,
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

    /// Load the meshes ONCE. Separate from `materialize` because the models outlive every edit:
    /// the editor re-materializes the world on each change, and rebuilding 77 procedural meshes
    /// to move one rock would stall for a second every time.
    pub fn build(self: *Env, scene: *gfx.Scene) void {
        self.scene = scene;
        const shader = scene.shader;
        // Index each mesh by its own kind so the array and the kinds can't drift out of
        // lockstep (props.INFO's comptime block already pins the table; this pins the models).
        for (&self.models, props.INFO) |*m, row| m.* = row.build(shader);
        self.ground = terrain(shader, GROUND_HALF);
        self.nprops = 0;
        self.nsolids = 0;
        self.nlights = 0;
        self.npools = 0;
    }

    /// Push the map's painted soil to the terrain shader. Separate from `materialize` on
    /// purpose: nothing about the prop list depends on the paint, so a brush stroke re-uploads
    /// 4 KB instead of re-expanding eight thousand props.
    pub fn uploadSoil(self: *Env, m: *const wf.Map) void {
        if (self.scene) |sc| sc.setSoil(&m.soil, m.half);
    }

    /// Turn a map into the world, IN PLACE. Not an `init()` returning a value: Env is ~450 KB
    /// of flat arrays, and a by-value return would copy that through the stack twice.
    ///
    /// Re-entrant on purpose — this is what the editor calls after every edit, so the edited
    /// map IS the live preview. Everything it touches is reset at the top; nothing accumulates.
    pub fn materialize(self: *Env, m: *const wf.Map) void {
        self.nprops = 0;
        self.nsolids = 0;
        self.nlights = 0;
        self.npools = 0;

        var p = Placer{ .e = self, .m = m };
        // Everything except the ground cover, in file order — later ops read what earlier ones
        // placed (ivy climbs standing stone; a belt rejects water already poured).
        for (m.slice(), 0..) |*o, i| {
            p.cur = @intCast(i);
            if (o.op != .cover) p.expand(o);
        }
        // …then the solid grid, because the cover scatter asks it where it may grow…
        buildSolids(self);
        const beforeCover = self.nprops;
        for (m.slice(), 0..) |*o, i| {
            p.cur = @intCast(i);
            if (o.op == .cover) p.expand(o);
        }
        // …and REBUILD it only if the cover pass actually laid down a collider. A stale grid is
        // a walk-through wall, so this cannot simply be skipped — but ground cover is flora,
        // and flora has no footprint, so in every real map the answer is no and the second full
        // pass over ~8k props was pure waste on a path the editor runs on every edit.
        var coverIsSolid = false;
        for (self.props[beforeCover..self.nprops]) |pr| {
            if (props.info(pr.kind).parts.len > 0) {
                coverIsSolid = true;
                break;
            }
        }
        if (coverIsSolid) buildSolids(self);
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

    /// The prop a ray hits first, as an index into `props` — the editor's world picking. A plain
    /// linear ray/sphere sweep over every instance: ~8k spheres on a CLICK is nothing, and going
    /// through the grid here would mean walking cells in ray order for no measurable gain.
    ///
    /// Each prop's sphere is centred half way up its mesh, not on its ground origin, so a click
    /// on a tower's parapet picks the tower rather than whatever weed is growing at its foot.
    pub fn pick(self: *const Env, origin: rl.Vector3, dir: rl.Vector3) ?usize {
        return self.pickIf(origin, dir, {}, struct {
            fn all(_: void, _: u16) bool {
                return true;
            }
        }.all);
    }

    /// `pick`, but only over the props whose OP the predicate accepts. The editor's layers need
    /// the filter INSIDE the sweep: rejecting after the nearest hit has won means a fern standing
    /// under a tree is unpickable, because the tree's far bigger sphere takes the ray and is then
    /// thrown away — which reads as the Decor layer refusing to select anything in a wood.
    pub fn pickIf(
        self: *const Env,
        origin: rl.Vector3,
        dir: rl.Vector3,
        ctx: anytype,
        comptime accept: fn (@TypeOf(ctx), u16) bool,
    ) ?usize {
        var best: ?usize = null;
        var bestT: f32 = std.math.floatMax(f32);
        for (self.props[0..self.nprops], 0..) |pr, i| {
            if (!accept(ctx, pr.op)) continue;
            const nfo = props.info(pr.kind);
            const c = v3(pr.pos.x, pr.pos.y + nfo.top * pr.scale * 0.5, pr.pos.z);
            const rad = @max(nfo.bound * pr.scale * 0.5, 0.35);
            const oc = mathx.subV(c, origin);
            const along = oc.x * dir.x + oc.y * dir.y + oc.z * dir.z;
            if (along <= 0) continue; // behind the eye
            const perp2 = (oc.x * oc.x + oc.y * oc.y + oc.z * oc.z) - along * along;
            if (perp2 > rad * rad) continue;
            if (along < bestT) {
                bestT = along;
                best = i;
            }
        }
        return best;
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

    /// Push this frame's torch/fire lights: the gfx.MAX_LIGHTS nearest the camera whose pool of
    /// light is actually ON SCREEN, each with its guttering applied. The world may hold far more
    /// than the shader can hold; the ones dropped are the furthest away, where a light contributes
    /// nothing anyway.
    ///
    /// THE FRUSTUM TEST IS A PERFORMANCE FIX, not a tidy-up. This used to accept any fire within
    /// `radius + 90` of the eye — which in the Fallen City is every fire in the region (the world
    /// holds 34), so `nLights` saturated at gfx.MAX_LIGHTS every single frame. `pointLights` runs
    /// per FRAGMENT and is called unconditionally, so the full-screen terrain pass alone was
    /// evaluating ~16M loop iterations for lights that were mostly BEHIND the camera. Tested
    /// against the same frustum the prop culler uses (View.visible, whose test sweeps seven
    /// headings), with the light's own radius as the sphere: a torch still lights its room the
    /// instant you look at it, and costs nothing at all when you don't.
    pub fn uploadLights(self: *const Env, scene: *gfx.Scene, view: *const View, t: f32) void {
        var picked: [gfx.MAX_LIGHTS]gfx.Light = undefined;
        var dist: [gfx.MAX_LIGHTS]f32 = undefined;
        var n: usize = 0;
        for (self.lights[0..self.nlights]) |wl| {
            // Off screen → it lights nothing you can see. The distance cap is unchanged from the
            // old bound, so nothing that WAS lit stops being lit; only the off-screen ones go.
            if (!view.visible(wl.base.pos, wl.base.radius, LIGHT_REACH)) continue;
            const d2 = mathx.dist2XZ(wl.base.pos, view.pos);
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

// ── placement: REPLAYING A MAP ─────────────────────────────────────────────────────────
// The world used to be authored here, as five paragraphs of Zig. It is authored in a MAP FILE
// now (worldfmt.zig) and this is the other half of that: the expansion of each op into props.
//
// Two rules the replay lives by:
//
//   ORDER IS MEANING. Ops run in file order, because later ops read what earlier ones placed:
//   `ivy` only climbs stonework that is already standing, a belt only rejects water that has
//   already been poured, and `cover` needs the solid grid built. Nothing here may reorder.
//
//   EACH OP DRAWS FROM ITS OWN STREAM (`op.stream()`), never a shared one. That is what keeps
//   an edit local — see worldfmt.zig's header. It is also why this file no longer holds a
//   world seed: there isn't one any more, there are 277 of them.

const Placer = struct {
    e: *Env,
    m: *const wf.Map,
    cur: u16 = 0, // the op being expanded, stamped onto every prop it places

    fn at(self: *Placer, kind: Kind, x: f32, z: f32, yaw: f32, scale: f32, rng: *mathx.Rng) void {
        self.atY(kind, x, 0, z, yaw, scale, rng);
    }

    // With an explicit Y — only water uses it, to stagger overlapping sheets out of z-fighting.
    fn atY(self: *Placer, kind: Kind, x: f32, y: f32, z: f32, yaw: f32, scale: f32, rng: *mathx.Rng) void {
        if (self.e.nprops >= MAX_PROPS) @panic("env: MAX_PROPS exceeded — raise the cap");
        self.e.props[self.e.nprops] = .{ .kind = kind, .pos = v3(x, y, z), .yaw = yaw, .scale = scale, .op = self.cur };
        self.e.nprops += 1;
        if (props.info(kind).light) |ls| self.addLight(x, y, z, scale, ls, rng);
        if (kind == .water) {
            // An init-time PANIC, like MAX_PROPS/MAX_SOLIDS — never a silent drop. A dropped pool
            // makes `inWater` lie about that sheet, and the flora scatter then grows grass and
            // brambles out in the middle of the lake.
            if (self.e.npools >= self.e.pools.len) @panic("env: water pool cap exceeded — raise Env.pools");
            self.e.pools[self.e.npools] = .{ .pos = v3(x, y, z), .radius = 13.0 * scale };
            self.e.npools += 1;
        }
    }

    fn addLight(self: *Placer, x: f32, y: f32, z: f32, scale: f32, ls: props.LightSpec, rng: *mathx.Rng) void {
        if (self.e.nlights >= MAX_LIGHTS) return; // fires past the cap simply don't light — never a crash
        self.e.lights[self.e.nlights] = .{
            .base = .{ .pos = v3(x, y + ls.y * scale, z), .col = ls.col, .radius = ls.radius * mathx.maxF(scale, 0.6) },
            .flicker = ls.flicker,
            .phase = rng.range(0, 60), // every flame guttering on its own beat
        };
        self.e.nlights += 1;
    }

    /// The full accept test for one scatter candidate: the op's `avoid` set, then the cover
    /// field, then any density gradient. ONE function because belt and disc had the same three
    /// clauses written out separately, and the cover-field literal drifting between the two
    /// would be invisible — one scatter quietly thinning at a different rate than its neighbour.
    fn accepts(self: *Placer, o: *const wf.Op, x: f32, z: f32, rng: *mathx.Rng) bool {
        if (self.rejects(o, x, z)) return false;
        // The cover field, mixed toward 1 so structures THIN where the flora does without
        // vanishing. Same field the ground cover uses, so a clearing is a clearing for
        // everything standing in it.
        if (o.field and rng.float() > FIELD_FLOOR + (1.0 - FIELD_FLOOR) * coverField(x, z)) return false;
        if (o.gAxis != .none and rng.float() > o.gradAt(x, z)) return false;
        return true;
    }

    /// The shared rejection test every scatter runs a candidate through. Which clauses apply is
    /// the op's own `avoid` set, so lilies can float on the water that grass must keep off.
    fn rejects(self: *Placer, o: *const wf.Op, x: f32, z: f32) bool {
        if (o.avoid.runway and self.m.onRunway(x, z)) return true;
        if (o.avoid.water and self.e.inWater(x, z, 1.04)) return true;
        if (o.avoid.clear and self.m.inClearing(x, z)) return true;
        if (o.avoid.solid) {
            // Don't grow through the world: the solid grid already knows what is here.
            var buf: [MAX_NEAR]collision.Solid = undefined;
            const probe = v3(x, 0.2, z);
            if (collision.blockedBy(probe, 0.35, self.e.nearSolids(probe, 1.4, &buf))) return true;
        }
        return false;
    }

    fn expand(self: *Placer, o: *const wf.Op) void {
        var rng = o.stream();
        switch (o.op) {
            .at => self.atY(o.kind, o.x, o.r1, o.z, o.yaw, o.scale, &rng),
            .belt => self.belt(o, &rng),
            .disc => self.disc(o, &rng),
            .ring => self.ring(o, &rng),
            .line => self.line(o, &rng),
            .ivy => self.ivy(o, &rng),
            .edge => self.edge(o, &rng),
            .cover => self.cover(o, &rng),
        }
    }

    // A scattered belt in a box. `n` is an ATTEMPT count, not a guarantee — rejection keeps the
    // world honest, and the clumping it leaves keeps a region from looking sown.
    fn belt(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        var i: i32 = 0;
        while (i < o.n) : (i += 1) {
            const x = rng.range(o.x, o.x1);
            const z = rng.range(o.z, o.z1);
            if (!self.accepts(o, x, z, rng)) continue;
            self.at(o.pick(rng), x, z, rng.range(0, 360), rng.range(o.sLo, o.sHi), rng);
        }
    }

    // An annulus scatter: shorelines, reed beds, talus, drowned ruin. `bias` bends the radial
    // distribution toward area-uniform, which packs a raft in around its rootstock.
    fn disc(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        var i: i32 = 0;
        while (i < o.n) : (i += 1) {
            const a = rng.angle();
            const t = rng.float();
            const d = o.r0 + (o.r1 - o.r0) * (t + (@sqrt(t) - t) * o.bias);
            const x = o.x + mathx.cosf(a) * d;
            const z = o.z + mathx.sinf(a) * d;
            if (!self.accepts(o, x, z, rng)) continue;
            self.at(o.pick(rng), x, z, rng.range(0, 360), rng.range(o.sLo, o.sHi), rng);
        }
    }

    // A ring of props about a centre — henges, stone circles, camps.
    fn ring(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        var i: i32 = 0;
        while (i < o.n) : (i += 1) {
            if (i == o.skip) continue; // the gap: a ring with every stone present reads as a fence
            const a = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(o.n));
            const r = o.r0 * rng.range(0.94, 1.06);
            const x = o.x + mathx.cosf(a) * r;
            const z = o.z + mathx.sinf(a) * r;
            if (self.rejects(o, x, z)) continue;
            self.at(
                o.pick(rng),
                x,
                z,
                mathx.degrees(-a) + 90 + rng.signed() * 12, // faces the centre, roughly
                rng.range(o.sLo, o.sHi),
                rng,
            );
        }
    }

    // A broken run from a→b: segments laid nose to tail, `chance` of each surviving. Both the
    // city's perimeter and the processional colonnade are this — one is a wall and one is a
    // row of columns, and the only difference is the kind mix and the spacing.
    fn line(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        const dx = o.x1 - o.x;
        const dz = o.z1 - o.z;
        const len = @sqrt(dx * dx + dz * dz);
        if (len < 1e-4 or o.r0 < 1e-4) return; // a zero-length or zero-step run would spin forever
        const ux = dx / len;
        const uz = dz / len;
        const yaw = mathx.degrees(std.math.atan2(-uz, ux)); // local +X is (cos yaw, −sin yaw)
        var t: f32 = o.r0 * 0.5;
        while (t < len) : (t += o.r0 * rng.range(1.0, 1.5)) {
            if (rng.float() > o.chance) continue; // a collapsed stretch
            const x = o.x + ux * t + rng.signed() * 0.6;
            const z = o.z + uz * t + rng.signed() * 0.6;
            if (self.rejects(o, x, z)) continue;
            self.at(o.pick(rng), x, z, yaw + rng.signed() * 6, rng.range(o.sLo, o.sHi), rng);
        }
    }

    // Sow a climber at the FEET of the stonework already standing inside a box. Ivy climbs: its
    // runners only make sense with a wall behind them, so this walks the props that are THERE
    // rather than scattering over ground — which is why op order matters.
    fn ivy(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        const n = self.e.nprops; // snapshot: the ivy we add must not seed more ivy
        for (self.e.props[0..n]) |pr| {
            switch (pr.kind) {
                .wall, .pillar, .broken, .block, .arch, .statue, .cottage, .chapel, .watchtower, .stairs, .monolith => {},
                else => continue,
            }
            if (pr.pos.x < o.x or pr.pos.x > o.x1 or pr.pos.z < o.z or pr.pos.z > o.z1) continue;
            if (rng.float() > o.chance) continue;
            const nfo = props.info(pr.kind);
            // Hug the base: just outside the prop's own footprint, so the runners lie against it.
            const a = rng.angle();
            const d = nfo.bound * pr.scale * rng.range(0.18, 0.42);
            self.at(o.kind, pr.pos.x + mathx.cosf(a) * d, pr.pos.z + mathx.sinf(a) * d, mathx.degrees(a), rng.range(o.sLo, o.sHi), rng);
        }
    }

    // ── THE EDGE: a cliff wall right round the world ────────────────────────────────────
    // The movement clamp sits just inside a rock face, so the world's edge reads as terrain
    // rather than as an invisible wall in open grass. Each segment's detailed face is its local
    // −Z, so each side takes the yaw that turns that face INWARD (north 180, south 0, east 90,
    // west 270). The step is a DEEP overlap against a 10.4 m segment: that is what turns a row
    // of separate rocks into one continuous escarpment.
    fn edge(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        if (o.r0 < 1e-4) return;
        const rim = self.m.half + 6.0; // the rock wall stands just outside the movement clamp
        var t: f32 = -rim;
        while (t <= rim) : (t += o.r0) {
            const jitter = rng.signed() * 1.6;
            self.at(o.pick(rng), t + jitter, -rim - rng.range(0, 2.5), 180 + rng.signed() * 7, self.ridge(o, t, rng), rng);
            self.at(o.pick(rng), t - jitter, rim + rng.range(0, 2.5), 0 + rng.signed() * 7, self.ridge(o, t + 91, rng), rng);
            self.at(o.pick(rng), rim + rng.range(0, 2.5), t + jitter, 90 + rng.signed() * 7, self.ridge(o, t + 213, rng), rng);
            self.at(o.pick(rng), -rim - rng.range(0, 2.5), t - jitter, 270 + rng.signed() * 7, self.ridge(o, t + 347, rng), rng);
        }
        // Talus and scrub spilling off the feet of the walls, so the base isn't a clean line.
        // Kept INSIDE half−4: the cliff mesh has its own talus reaching ~4 m in, and a boulder
        // dropped into that shows as a wrong-coloured lump growing out of the rock.
        var i: i32 = 0;
        while (i < o.n) : (i += 1) {
            const along = rng.range(-rim, rim);
            const off = rng.range(self.m.half - 20, self.m.half - 4);
            const pos: [2]f32 = switch (rng.intn(4)) {
                0 => .{ along, -off },
                1 => .{ along, off },
                2 => .{ off, along },
                else => .{ -off, along },
            };
            const kind: Kind = if (rng.float() < 0.45) .boulder else if (rng.float() < 0.7) .rocks else .bush;
            self.at(kind, pos[0], pos[1], rng.range(0, 360), rng.range(0.8, 1.5), rng);
        }
    }

    // Segment scale as a function of WHERE ALONG the wall it sits: two long sines (~90 m and
    // ~37 m) plus a little noise. Purely random per-segment scale gives the crest hedge-trimmer
    // jitter; summed long waves read as topography — headlands and saddles you see coming.
    fn ridge(self: *Placer, o: *const wf.Op, along: f32, rng: *mathx.Rng) f32 {
        _ = self;
        const mid = (o.sLo + o.sHi) * 0.5;
        const amp = (o.sHi - o.sLo) * 0.5;
        return mid + amp * (0.62 * mathx.sinf(along * 0.070) + 0.31 * mathx.sinf(along * 0.170 + 1.9)) + rng.signed() * amp * 0.16;
    }

    // ── the seeded ground cover ─────────────────────────────────────────────────────────
    // A stratified scatter over the whole world: one candidate per LATTICE cell at a jittered
    // position, so coverage is even without the O(n·m) rejection sampling the small world used.
    // Kind follows the ZONE it lands in; DENSITY follows that zone's peak times the cover field.
    fn cover(self: *Placer, o: *const wf.Op, rng: *mathx.Rng) void {
        const pitch = o.r0;
        if (pitch < 0.1) return;
        const half = self.m.half;
        const n: i32 = @intFromFloat(@ceil(2 * half / pitch));
        var iz: i32 = 0;
        while (iz < n) : (iz += 1) {
            var ix: i32 = 0;
            while (ix < n) : (ix += 1) {
                const bx = -half + (@as(f32, @floatFromInt(ix)) + 0.5) * pitch;
                const bz = -half + (@as(f32, @floatFromInt(iz)) + 0.5) * pitch;
                const x = bx + rng.signed() * pitch * 0.48;
                const z = bz + rng.signed() * pitch * 0.48;
                const zone = self.m.zoneAt(x, z) orelse continue;
                if (rng.float() > zone.density * coverField(x, z)) continue;
                if (self.m.inClearing(x, z)) continue;
                // Water uses a TIGHTER inset than a belt's: reeds may stand at the rim, but
                // nothing grows mid-lake.
                if (self.e.inWater(x, z, 0.97)) continue;
                if (self.m.onRunway(x, z)) continue;
                var buf: [MAX_NEAR]collision.Solid = undefined;
                const probe = v3(x, 0.2, z);
                if (collision.blockedBy(probe, 0.35, self.e.nearSolids(probe, 1.4, &buf))) continue;
                // A mix-less zone grows nothing (the accessor says so rather than indexing an
                // `undefined` slot — see wf.Zone.pick).
                const kind = zone.pick(rng) orelse continue;
                self.at(kind, x, z, rng.range(0, 360), rng.range(o.sLo, o.sHi), rng);
            }
        }
    }
};

// A prop-local (x, z) offset carried through an instance's yaw + scale into world offsets.
// Same convention the colliders use: local +X → (cos, −sin), local +Z → (sin, cos).
fn localToWorld(lx: f32, lz: f32, yaw: f32, scale: f32) [2]f32 {
    const th = mathx.radians(yaw);
    const c = mathx.cosf(th);
    const s = mathx.sinf(th);
    return .{ scale * (lx * c + lz * s), scale * (-lx * s + lz * c) };
}

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

// ── the indexes ────────────────────────────────────────────────────────────────────────

// Footprint colliders for every solid prop: each kind's local Part list, rotated by the
// instance yaw and scaled. Each solid carries its part's own TOP height, so arrows thunk into
// a chapel wall but arc clean over a causeway kerb.
fn buildSolids(e: *Env) void {
    // RESET, so this is idempotent: materialize runs it twice (once for the cover scatter to
    // query, once after, in case a later op added colliders) and an appending version silently
    // doubled every footprint in the world.
    e.nsolids = 0;
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
    var x: f32 = -wf.DEFAULT_HALF;
    while (x <= wf.DEFAULT_HALF) : (x += 3) {
        var z: f32 = -wf.DEFAULT_HALF;
        while (z <= wf.DEFAULT_HALF) : (z += 3) {
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

test "the SHIPPED map parses, and its zones cover every reachable position" {
    // Against the real file, not a fixture. The map IS the world now, so a map that fails to
    // parse is a game that starts in a void — and this is the cheapest place to find out, well
    // before a launch. Every point inside the playable bounds must resolve to a zone with a
    // non-empty flora mix and a plausible density; a gap is a bald patch you can walk to.
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    wf.load(wf.START_MAP, m, &line) catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest; // run from another cwd
        std.debug.print("{s} failed to parse at line {d}\n", .{ wf.START_MAP, line });
        return e;
    };
    try std.testing.expect(m.nops > 0);

    var x: f32 = -m.half;
    while (x <= m.half) : (x += 7) {
        var z: f32 = -m.half;
        while (z <= m.half) : (z += 7) {
            const zone = m.zoneAt(x, z) orelse return error.NoZone;
            try std.testing.expect(zone.nmix > 0);
            try std.testing.expect(zone.density > 0.1 and zone.density <= 1.0);
            for (zone.mix[0..zone.nmix]) |k| try std.testing.expect(props.info(k).flora);
        }
    }
}

test "every generator op in the shipped map has its own seed" {
    // Two ops sharing a seed AND a shape would place the same instances twice, and a seed left
    // at zero is an op nobody gave a stream to. Both are silent — the world just looks subtly
    // repetitive — so they are asserted rather than eyeballed.
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    var line: usize = 0;
    wf.load(wf.START_MAP, m, &line) catch |e| {
        if (e == error.FileNotFound) return error.SkipZigTest;
        return e;
    };
    for (m.slice(), 0..) |o, i| {
        if (o.op == .at) continue; // literals draw nothing
        try std.testing.expect(o.seed != 0);
        for (m.slice()[0..i]) |prev| {
            if (prev.op != .at) try std.testing.expect(prev.seed != o.seed);
        }
    }
}

test "the cliff ring stands outside the movement clamp, and inside the grid" {
    // PLAY_HALF (game.zig) insets the map's half; the rock must be beyond that or the player is
    // stopped by air with the cliff still ahead of them.
    try std.testing.expect(RIM_OUT > 0);
    // CLIFF_BOUND is a hand-copied mirror of the mesh's own bound, because MAX_HALF has to be a
    // comptime value and `props.info` is a runtime lookup. Pin them together or the ceiling
    // silently stops matching the rock it is sized for.
    try std.testing.expectApproxEqAbs(CLIFF_BOUND, props.info(.cliff).bound, 1e-4);
    // The DEFAULT map must fit inside what the grid can index, or everything past the boundary
    // piles into the edge cells and a cell that cannot be rejected is thirty props tested one by
    // one — the culling still works, it just stops being cheap.
    try std.testing.expect(wf.DEFAULT_HALF <= MAX_HALF);
    // …and the ground quad has to clear the far corner plus the haze reach, or the plane's own
    // edge shows as a hard line under the sky from the corners of the world.
    try std.testing.expect(GROUND_HALF > wf.DEFAULT_HALF + 200);
}

test "the map's half drives the world, not a constant in this file" {
    const m = try std.testing.allocator.create(wf.Map);
    defer std.testing.allocator.destroy(m);
    m.blank("sized");
    // `blank` writes the default, and a map that says something else is obeyed. This is the
    // regression that mattered: the clamp used to be comptime, so a resized map moved its cliffs
    // and its ground cover and left the hero walled in at the old bound.
    try std.testing.expectApproxEqAbs(wf.DEFAULT_HALF, m.half, 1e-4);
    m.half = 120;
    try std.testing.expectApproxEqAbs(@as(f32, 118), m.half - PLAY_INSET, 1e-4);
}

