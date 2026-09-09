# Cliff and cave authoring research

Researched and implemented September 8, 2026. The brief is fast placement, attractive defaults, and enjoyable editing. Detailed customization can wait. StarCraft II is the main interaction reference.

## What the existing editors teach us

| System | Authoring model | Useful lesson for this editor |
| --- | --- | --- |
| StarCraft II | Paint cliff levels, connect ramps, sculpt height separately | A cliff stroke should create a usable raised area and its faces together. |
| Fortnite / Unreal | Landscape holes plus underground volumes and cave pieces | Entrances must coordinate terrain, interior geometry, and traversal. |
| Unity Terrain | Brush an opacity mask into the heightfield | A hole alone is not a complete cave tool. |
| Roblox Studio | Add/subtract/smooth terrain with brush and plane controls | Keep the brush predictable while the surface changes underneath it. |
| Skyrim | Reusable kits with consistent connections | Invest in attractive defaults and reliable joins rather than exposing every parameter. |
| Deep Rock Galactic | Authored room shapes, connected tunnels, constrained procedural detail | Establish useful space before adding surface irregularity. |
| Historical CryEngine voxel objects | Local voxel volumes combined with a heightfield | Volumetric editing can be localized, but still requires an explicit workflow. |
| Godot Voxel Tools / Transvoxel | Signed-distance volumes and meshes with transitions between resolutions | An option for future stacked caves, not a necessary prerequisite for fixing this editor. |

### StarCraft II: the closest match

Blizzard's original Terrain Module tutorial, preserved in the SC2 editor documentation, separates cliff editing from ordinary height sculpting. Raise/Lower Cliff and Add Ramp are brush operations, with size, shape, and cliff type controls. The tutorial builds the terrain layout by placing cliff levels and then connecting them. [Blizzard tutorial archive](https://s2editor-guides.readthedocs.io/Classic_Tutorials/01_Terrain_Module/1/)

Our application: make a complete cliff the result of a stroke. The previous workflow could require shaping a height difference, flagging its edge, choosing a decorative piece, and checking its fit. Those steps are too indirect for the requested experience. The normal Ground palette now starts with Raise cliff, Lower cliff, Ramp, and Waterfall; sculpting and painting are separate groups. Height presets are 3, 6, and 12 metres. This borrows the interaction model, not SC2's implementation or assets.

### Fortnite and Unreal: the cost of manual assembly

Epic's UEFN cave tutorial uses Landscape Visibility, a Fort Underground Volume, and gallery tunnel pieces. It recommends placing entrances on accessible ground, fitting the volume to the cave, covering protruding joins with boulders, and walking the result. [Epic's cave tutorial](https://dev.epicgames.com/documentation/en-us/fortnite/making-a-cave-in-unreal-editor-for-fortnite)

Our application: automate the joins and preserve clear passage space. Requiring the user to place rocks to disguise a broken opening would carry the current frustration into the new tool. Cave air now also cuts cliff faces, their backing geometry, and the terrain strips at their feet. Automatic cliff dressing is omitted at entrances where it would obstruct the passage. The Entrance tool previews a connection before changing the map and refuses a slope too steep for its intended grade.

### Unity: a terrain hole is only one ingredient

Unity's Paint Holes modifies a texture mask that hides parts of the terrain. It supports lighting, collision, and navigation baking. Unity explicitly documents aliased hole edges and suggests concealing them with other geometry. [Unity 6.0 Paint Holes manual](https://docs.unity3d.com/6000.0/Documentation/Manual/terrain-PaintHoles.html)

Our application: retain a shared contour for terrain, walls, floor, and ceiling. A visibility mask followed by manual mesh placement is useful engine infrastructure, but insufficient as the everyday cave experience requested here. We already have a floor/roof field and can produce the entire shell automatically.

### Roblox: direct manipulation and a stable brush

Roblox Studio documents Add, Subtract, Smooth, Flatten, and related terrain brushes. Brush shape and size are visible, and plane locking constrains manipulation. Smooth can be invoked temporarily while sculpting. [Roblox Terrain Editor](https://create.roblox.com/docs/studio/terrain-editor)

Our application: carve and fill should be opposites, dimensions should mean what the preview shows, and the terrain changing must not pull the brush away from the mouse. Cave and cliff strokes now use a construction plane through the initial hit for the duration of the gesture. Underground picking starts on the visible floor. Strokes sweep the distance between samples, so a fast mouse movement does not leave isolated stamps or disconnected passages. The interface displays full passage width rather than labeling a radius as width.

### Skyrim: quality comes from the system of parts

Joel Burgess and Nathan Purkeypile describe Bethesda's modular approach as a system of reusable pieces with common connection rules. Their account also discusses visible repetition and why copying entire furnished rooms produced recognizable repetition. [Firsthand GDC 2013 account](https://www.gamedeveloper.com/design/skyrim-s-modular-approach-to-level-design)

Our application: simplify the vocabulary and make its combinations reliable. Tunnel and Chamber presets supply useful dimensions. Premade cliff pieces remain available for deliberate dressing, but choosing and seating a piece is no longer required to create ordinary cliff terrain. Cosmetic variation should help the assembled landscape without moving its walkable boundary.

### Deep Rock Galactic: constrain the detail around usable space

Ghost Ship's developer account describes authored rooms made from intersecting volumes, joined by tunnels. Inner and outer boundaries limit how far procedural detail can encroach. Room templates, traversal, and wayfinding come before biome-specific noise and decoration. [Developer announcement](https://store.steampowered.com/news/app/548430/view/4593196713081471258), [readable archive of the developer's post](https://devtrackers.gg/deep-rock-galactic/p/8cd5ca9c-below-decks-at-ghost-ship-cave-generation-in-deep-rock-galactic)

Our application: floor continuity and clearance are primary. Cave defaults provide gently vaulted roofs and restrained wall relief. Recarving preserves a shaped floor; a larger headroom setting can expand an existing roof. Detail stays small enough that it does not consume the passage. This is an authoring lesson, not a claim that our representation reproduces DRG's volumetric terrain.

### Historical CryEngine: local volumes, explicit planes

CryEngine's older voxel-object documentation describes small local voxel volumes alongside a heightfield, with create/subtract/blur operations and plane-oriented editing. The documentation explicitly marks voxel objects deprecated from CryEngine 3.5 onward. [Historical CryEngine documentation](https://www.cryengine.com/docs/static/engines/cryengine-3/categories/1114113/pages/1048838)

Our application: a full volumetric replacement of the outdoor world is not the only architecture. The stable editing-plane interaction is useful now. The deprecated implementation is historical evidence, not a dependency recommendation.

### Voxel Tools and Transvoxel: when a representation change would help

Godot Voxel Tools documents smooth terrain built from signed-distance data and meshing, including the consequences of editing and level of detail. Eric Lengyel's Transvoxel algorithm specifically addresses joining meshes sampled at different resolutions. [Voxel Tools smooth terrain](https://voxel-tools.readthedocs.io/en/latest/smooth_terrain/), [Transvoxel author's explanation](https://transvoxel.org/)

Our application: true three-dimensional volumes would become appropriate for independently stacked tunnels, arbitrary overhangs, and runtime excavation. They also introduce different persistence, collision, meshing, and editing requirements. Our observed floor spikes and mouth fins were errors in existing same-resolution sampling and clipping; adding Transvoxel would not automatically repair them.

## Changes made here

The normal workflow is now:

1. **Ground → Cliffs:** choose a height and click or drag. A stroke holds one target height and joins its terrain and cliff faces. Lower cliff cuts an area down with the same interaction.
2. **Ramp:** drag from the foot to the top. The preview shows the connection; release builds it when the run supports the rise.
3. **Caves → Carve:** choose Tunnel or Chamber, then click or drag. Floor fitting is automatic, existing floors are preserved, and fast strokes remain connected.
4. **Entrance:** drag from outdoor ground into the cave. A graded floor connects the endpoints; overly steep connections leave the map unchanged.
5. **Inside / Surface:** hide the ceiling and terrain above the cave to work inside, or show them to inspect the hill. The adjacent edit button opens Ground on the visible level. Underground Ground tools shape the floor and ceiling separately.
6. **Waterfall:** paint an existing cliff edge. Shift restores dry rock. The cave panel also has an Add a waterfall shortcut. Water is a transparent, animated curtain with a splash at its foot; it leaves the cave floor and entrance intact.
7. **Fill:** paint rock back. Existing undo/redo applies to terrain gestures.

The geometry work addresses identifiable causes rather than hiding them with extra props:

- The lighting texture uses the same extrapolated roof heights and lattice coordinates as the mesh, and includes the shallow wall relief in its shelter coverage, preventing sunlight seams at the ceiling.
- Empty cave corners no longer interpolate an underground floor toward an unpainted datum, which produced triangular spikes.
- Terrain and ceiling meet at their actual intersection instead of dropping an entire cell's roof and building a vertical band around it.
- Ceiling meshes are separate from floor/wall meshes, so hiding the ceiling actually removes it from the editor view.
- Cave air removes cliff wall and backing triangles too; it is not just a hole in the heightfield.
- Cave surface colours vary continuously instead of changing abruptly per wall panel. Stone texture projections blend across three axes, avoiding vertical stretching on walls.
- Cliff rocks are more embedded, with smaller protruding lobes. The exact terrain cut remains stable.

## Deliberately deferred

Arbitrary brush noise controls, extensive geological presets, graph authoring, manual seam correction, and a wholesale voxel rewrite do not serve this first usability pass. Advanced legacy sculpting and prop tools remain under All tools or their existing layers; they are not prerequisites for the simple workflow.

The map still stores one underground floor/ceiling interval per horizontal position. Separate chambers and connected tunnels are supported; two independent caves directly above one another are not. The brushes improve the default shell, not automatic complete biome dressing or lighting design.

## Reproduction and verification

`check.cmd` checks both executable and test roots. `zig build test` exercises the existing suite plus terrain regressions for continuous strokes, floor preservation, deep cave boundaries, ramp continuity, roof/hill intersections, actual cliff opening area, and waterfall save/load without changing terrain or caves.

Build with the project's Zig 0.14.1 toolchain, then run `zig-soulslike.exe --shot --shot-only terrain_editor_study`. The study builds a temporary scene in memory with a plateau, lowered area, ramp, tunnel, chamber, and underground lights; it writes nine PNGs under `shots/terrain_*.png` without saving over an authored world. The Inside/Surface pair uses the same camera. Existing `--shot-land` cave shots cover previously authored cave geometry as well.

Waterfalls are an authored visual cliff option. They do not simulate a river supply or automatically flood the landing area; use the existing Water brush to add a pool when desired.

Validation completed: normal `build.cmd`, full unit suite, then the focused cave/terrain regressions after the final lighting correction. The nine-scene study was rendered and inspected with the normal executable; the existing thirteen cave landscape views also rendered successfully. The waterfall save/load regression checks both cliff height sampling and unchanged cave data.

Final captures: [cliff and cave tools](../shots/terrain_04_inside_editor.png), [waterfall entrance](../shots/terrain_07_waterfall_cave.png), [behind the waterfall](../shots/terrain_08_behind_waterfall.png), [waterfall brush](../shots/terrain_09_waterfall_editor.png). These PNGs are local, generated artifacts under the ignored `shots` directory.
