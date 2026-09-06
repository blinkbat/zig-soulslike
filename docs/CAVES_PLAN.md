**Caves beneath existing terrain — implementation handoff for Opus**

Prepared 2026-09-06 from the current source. Planning only; no cave implementation has been made.

The owner selected caves beneath existing terrain, with real entrances and a hillside that remains walkable overhead. They approved carving with editor brushes and explicitly asked that the editor be easy to use. Deliver a usable authoring feature, not merely a cave mesh or a demonstration room. Preserve the project's movement, combat, art, and build laws in AGENTS.md.

**Proposed scope**

Support connected underground chambers and passages, sloping floors, variable headroom, entrances through hillsides, and surface travel above them. Use the existing map, renderer, props, actors, and save system.

The proposed first representation has one underground floor/ceiling interval per horizontal position, in addition to the outdoor surface and existing decks. Multiple disconnected caves are possible; two underground tunnels crossing at different elevations are outside this first representation. Make that limitation explicit before implementation. Do not present this as arbitrary three-dimensional excavation. If stacked underground passages become a requirement, change the representation before building editor tools.

Runtime digging, destructible terrain, independent underground liquid levels, new monsters, and cave-specific progression are separate features. Existing outdoor maps must retain their behavior.

**Verified starting points**

| Area | Current behavior and consequence |
| --- | --- |
| src/world/worldfmt.zig | Terrain is a quantized height lattice with a cliff field; byte grids round-trip as run-length encoded text. Map also owns actor placements, locations, and starts. |
| src/gfx/gfx.zig | HEIGHT_N = 224, so the 560 m map has roughly 2.51 m between terrain vertices. Do not assume narrow passages will look or collide well at this spacing. |
| src/world/env.zig | standAt takes the maximum of terrain and an eligible deck. A cave floor below terrain cannot work through this function unchanged. |
| src/world/env.zig | Terrain uses tiled meshes and partial sculpt rebuilds. replay, adoptHeight, heightStale, sculptHeight, and buildTile jointly own synchronization. |
| src/core/collision.zig | Solids have an XZ shape and a vertical interval. Actor push-out is lateral; this does not supply a general ceiling solver. |
| src/core/camera.zig | followClear samples ground along the camera boom and clamps above a floor. It does not sweep against cave walls or ceilings. |
| src/game.zig | Many effects and projectiles call groundAt directly. CamFloor calls standAt. Movement, grounding, and world-space attacks need separate auditing. |
| src/foes/foe.zig | Shared spawn/reset paths derive home heights from Map.heightAt. Underground placement must survive these paths and respawn. |
| worldfmt.zig and game.zig | Weather locations are XZ rectangles; weather levels blend globally around the hero. A surface and a cave underneath share the same location lookup. |
| src/gfx/shaders.zig | Sky ambient is global; point lights have distance attenuation but no wall visibility test. A roof alone will not produce correct interior lighting. |
| src/ui/editor.zig | Undo snapshots store complete Map values. Picking, camera focus, and placement resolve against outdoor ground. |
| src/save.zig | Saves preserve a world position, but subsequent grounding/reset must preserve its floor. |

The working tree already contains substantial unrelated changes, including world, game, editor, shots, and foe files. Read fresh diffs before editing shared files. Preserve those changes; do not reset, commit, branch, or push. The machine note refers to docs/MODEL_ANIMATION_PASS.md, but that file is absent in this checkout.

**1. Establish the spatial contract**

Add a small headless cave module, provisionally src/world/caves.zig, for data, sampling, brush operations, and derived topology. Keep GPU ownership in the rendering/environment layer. Avoid an import cycle: the cave data module must not import worldfmt if Map contains its types. Reuse existing math, grid, and interpolation helpers.

Represent excavated volume using a horizontal coverage field plus floor and ceiling fields. Specify vertex versus cell indexing, interpolation, boundary ownership, and quantization in one place. Reconstruct smooth boundaries rather than rendering square painted cells. Resolve ambiguous contour cases consistently across neighboring tiles.

First test a narrow corridor, diagonal passage, and curved chamber on a full-size map. Select aligned subdivisions of terrain cells or sparse cave tiles with fixed world-space spacing. Measure memory, brush cost, and rebuild cost before choosing. Do not multiply large global grids through the undo ring without measuring memory.

| Query responsibility | Required result |
| --- | --- |
| Support below an actor | Height, normal, and surface identity, with step allowance and previous support/position. May return no support. |
| Occupancy | Whether a world-space point or body volume is in solid rock, outdoor air, or excavated air. |
| Motion sweep | Earliest contact, normal, and remaining travel for a body or projectile. |
| Cover | Whether solid world geometry separates two points. |
| Shelter | Whether a point is covered, with a spatial transition near an entrance. |

Preserve groundAt(x,z) as an explicit outdoor-land query for callers that need the surface. Audit consumers rather than changing its meaning globally.

An actor below the surface must never be lifted onto terrain above its head. An actor on the hillside must never attach to the cave floor below. Height alone cannot establish accessibility: reject movement through intervening rock and use real entrance connectivity. Jumps and falls must retain support continuity without making a stale surface identity permanent.

**2. Add persistence and surface-aware placements**

Extend .world with versioned, validated cave data using the existing parser/writer conventions. Absent cave records mean no caves. Validate dimensions, finite heights, floor/ceiling ordering, coverage values, and bounds. Include invalidation in reload, undo/redo, resizing, sculpting, and replay.

Persist the intended surface for foes, NPCs, the player start, and props where necessary. Existing records default to their current outdoor behavior. Prefer an explicit surface choice plus a local height offset over making authors calculate a negative lift from the hilltop.

If a selected cave floor is erased, show invalid placements in the editor and reject invalid play placement rather than silently relocating objects above ground. Trace save load, bonfire return, death drops, map reset, and enemy home positions. Serialized surface identity must not depend on generated mesh/collider indices. Test legacy maps and saves.

**3. Prove geometry with one real entrance**

Build a test map containing a sloped hill, passage, and chamber. Keep the surface over the chamber. Cave floors, walls, and ceilings must be closed and have correct inward-facing normals.

An entrance is an intersection between excavated volume and outdoor surface. Clip terrain and cliff geometry to that intersection and generate exposed rock thickness around the mouth. Share intersection vertices and edge decisions between terrain, cave shell, and collision. Skipping cells or deleting whole triangles can create cracks, abrupt lips, or a shaft where the author expected a hillside opening.

Respect painted cliffs, stairs, tile boundaries, and diagonal entrances. Sculpting the hill afterward must rebuild affected intersections. Show a diagnostic when carving leaves insufficient roof thickness; do not silently destroy the hill.

Reuse stone materials and seeded irregularity. Put larger variation into chamber outlines, wall lean, and ceiling height; keep relief shallow. Collision must track meaningful protrusions. Avoid identical repeated tube sections and disconnected decorative boulders masquerading as sealed walls.

Include caves in view bounds, shadow caster selection, shader switching, and mesh lifetime management. Releasing cave meshes must not unload shared shaders. Explicitly initialize all new resource flags/counters on alloc.create paths.

**4. Make traversal physically correct**

Address terrain-only assumptions at shared movement boundaries: standAt, step checks, slope/gradient reads, brink handling, airborne movement, and actor grounding. Preserve immediate input-to-ground-speed mapping.

Check body volume, not feet alone. A jump must stop at a ceiling; a large creature must be refused by a passage it cannot fit through. Preserve sliding and existing movement semantics. Sweep across the whole frame so sprinting, rolling, charging, and low frame rates cannot cross walls.

Use shared world collision for hero and foes. Creatures must never inspect player inputs or committed actions. Narrow caves change physical possibilities without adding input-reading decisions.

Test entry/exit on a slope, bodies directly above and below each other, falling through an opening, blocked jumps, wall sliding, and oversized bodies. Include fast movement and multiple frame rates.

**5. Route gameplay through the correct floor**

Inventory direct heightAt/groundAt consumers: outdoor geography, actor support, effect placement, or collision. Record intentional outdoor queries left in place.

Update shared foe reset/home logic, placement, loot, pickups, chests, bonfires, spirit summons, corpses, and surface-bound effects. Projectiles and spells below the hill must not impact its top because it shares their XZ coordinate.

Sight, lock-on eligibility, melee, projectiles, and interactions must honor intervening rock. A surface actor cannot hit a cave actor through the roof. Filter spatial regions by height/domain where they drive weather, encounters, triggers, or interactions; a surface boss room must not claim a cave below.

Prove existing enemy steering on a bent passage. If it fails, add the smallest shared connectivity/navigation extension that solves the observed problem. Do not duplicate navigation per enemy.

**6. Make the camera safe inside**

Sweep a camera volume from the shoulder target toward its desired position against walls, ceilings, floors, and the entrance rim. Account for the near plane: the current near clip is 0.55 m, so a point ray is insufficient.

Pull inward immediately when obstructed and recover outward smoothly using the existing convention. Resolve blocked shoulder offsets and targets near walls. Do not clamp the underground camera to outdoor ground.

Verify free look, aiming, lock-on, a large target, low ceilings, corner turns, and entering backward. Preserve outdoor framing. Cave shells stay opaque during gameplay; prop fading must not dissolve the hill to reveal the hero.

**7. Make lighting and weather spatial**

Derive interior lighting from fragment/object position and shelter, not a global hero-inside flag. From inside the mouth, the exterior stays in daylight while the chamber stays sheltered. From outside, the visible chamber is already dark.

Reduce sky ambient and sky rim under cover, retain torch/body lights, and preserve direct daylight through the opening. Point lights need visibility so an underground flame cannot illuminate the hillside above or a sealed neighboring cavity. Room identity can accelerate rejection, but cannot replace visibility around a bend.

Design GPU field data alongside the CPU sampler and verify agreement. Inspect texture bindings: the scene currently occupies high slots through 17. Do not assume another sampler/texture unit is available. Budget or repack deliberately and measure fragment cost.

Rain and outdoor effects stop at shelter while remaining visible outside the mouth. Handle particles crossing the boundary, not just the hero's location. Surface water must not apply wading or liquid damage in dry cave air beneath it. Independent underground liquid levels remain separate work.

The editor may use a neutral work light in cutaway view, clearly identified as a viewing aid.

**8. Make authoring discoverable**

Add a dedicated Caves layer. Use visible tool names; icons supplement the words. Entering Caves exposes underground space automatically. Keep a persistent Surface / Underground viewing choice available when switching to Props, Interactables, or Units, so furnishing does not require repeatedly fighting the roof.

| Tool or control | Author experience |
| --- | --- |
| Carve | Drag connected passages; enlarge the brush for chambers. Preview footprint and vertical extent. |
| Entrance | Drag from outdoor ground toward the cave. Preview the opening and connecting grade, including whether it is walkable. Do not require hand-calculated ramps. |
| Fill | Restore rock under the brush. Preview objects whose supporting floor will be removed. |
| Floor height | Clearly labelled world height; sample an existing floor when useful. Keep the value pinned during a stroke. |
| Ceiling height | Show ceiling height and resulting headroom together. Keep floor/ceiling values valid. |
| Brush size | Metres, with existing bracket shortcuts. Show passage width where useful. |
| Cutaway | Expose the interior while retaining a readable outline of surface and cave boundaries. |
| Sample existing cave | Visible button or documented modifier picks floor/ceiling settings. No hidden mandatory shortcuts. |
| Play here | Start on the selected valid cave floor with real camera/lighting; return to the same editing view. |

Keep the primary panel short: three tools, size, floor, ceiling/headroom, and viewing aid. Keep resolution, seeds, and diagnostics outside the normal flow. Use concise feedback for insufficient cover, an impassable entrance, and invalid placement.

Cursor picking targets the selected cave surface or a stable construction plane when carving into solid terrain. Hidden terrain must not intercept the brush. Projection, preview, painting, object placement, and selection must agree.

Interpolate brush travel so fast drags cannot leave disconnected stamps. One drag is one undo step; no-op clicks create no undo step. Rebuild affected tiles and neighbors with immediate feedback.

Validate this first-use sequence: open Caves; set a floor under the hill; carve chamber and passage; drag an entrance to them; place a light and enemy in Underground view; Play here; save and reload. A panel screenshot alone does not prove usability.

**9. Keep maps and culling honest**

Separate surface and underground editor overlays and picking. Underground exploration must not reveal surface terrain as though the hero explored it. Specify a minimal cave representation in the character map: an underground layer or an explicit indication that interiors are not mapped yet. Do not draw underground enemies/fires as outdoor content.

Culling bounds must include cave depth and avoid outdoor-floor assumptions. Test a deep camera and a bright exterior seen through the entrance. Avoid drawing every cave everywhere as the edited area grows.

**10. Execute in reviewable milestones**

| Milestone | Deliverable and exit condition |
| --- | --- |
| A: Data and queries | Resolution study, validated persistence, contextual support, occupancy tests. Same XZ correctly selects surface or cave. |
| B: Geometry and traversal | Real entrance and chamber beneath a walkable hill; continuous movement and matching collision. Inspect shots now. |
| C: Editor | Carve/entrance/fill, cutaway, placement, undo, save/reload, and Play here. Complete this before polishing art. |
| D: Gameplay and camera | Enemy traversal, fast movement, ceilings, projectiles, drops, restoration, and camera work underground. |
| E: Environment | Spatial lighting, shelter, light containment, map behavior, culling, and rock variation. |
| F: Regression and handoff | Checks, tests, required shots, performance measurements, and concise authoring documentation. |

Each milestone retains the previous behavior. Do not decorate the chamber before support selection, entrance clipping, and authoring are proven.

**Acceptance matrix**

| Case | Pass condition |
| --- | --- |
| Same XZ, two bodies | One stays on the hill, one in the cave; neither sees or hits through rock. |
| Entrance | Walk both directions without teleport, invisible step, camera breach, or terrain crack. |
| Painted cliff | Mouth, cliff facing, collision, and terrain agree. |
| Fast motion | Sprint, roll, projectiles, and large attacks cannot tunnel through walls/roofs. |
| Headroom | Hero jumps and tall creatures obey actual clearance. |
| Combat and drops | Floor effects stay underground; loot and death drops remain reachable. |
| Persistence | Save/load, death/rest, enemy reset, and map reload preserve the intended floor. |
| Environment | Dry interior, outdoor rain visible at mouth, no surface liquid damage below, no light through rock. |
| Editing | Create, connect, fill, undo/redo, furnish, play, save, and reload through visible controls. |
| Re-authoring | Sculpt hill, adjust cave heights, and resize without stale holes, collision, or resources. |
| Old maps | No cave records retains existing terrain, movement, placement, lighting, and map behavior. |
| Performance | Record affected-tile rebuild time, undo memory, draw counts, and frame cost against pre-change scenes. |

Use worlds/test_caves.world as the bench; keep cave content out of the shipped map during development. Include a diagonal entrance at a tile boundary, bent passage, chamber, low section, and outdoor path directly overhead.

Add focused stages to shots.runShots with the shot hour pinned. Required views: exterior mouth, close interior, interior looking out, overhead surface, underground cutaway, and actual editor panel with brush preview. Add a bright-background shot; inspect for magenta below the intended opening/skyline. Derive framing so the camera exposes the tested geometry.

Run check.cmd during edits. Run focused tests with the vendored Zig toolchain using build test -Dtest-filter=cave, then the full unit suite once integrated. Register new modules in main.zig's test block. Build once clean; use --prefix zig-out-dev if the normal executable is locked. Use the shot harness for automated visual verification; do not launch an interactive game to check the work.

Finish with an authoring guide, the explicit one-underground-interval limitation, actual test/screenshot results, measured performance, and any incomplete acceptance cases. Rendering alone does not satisfy the plan: caves must be conveniently authored, revisited after saving, and fought in.
