# AGENTS.md — zig-soulslike

A third-person **soulslike** prototype in native **Zig 0.14.1 + raylib**, founded on the sibling
`../zig-rts` rendering engine (procedural-mesh `Builder`, single-sun shadow-map pipeline).

Keep this file lean. Prefer no comments in code; write succinct ones for novel/edge cases.
Reuse existing helpers before adding new code. Don't make ad-hoc product/design decisions —
ask. The owner (David) drives the design; implement what's asked and nothing extra.

## The laws (owner's, non-negotiable)

- **NO HITSTOP. EVER.** No freeze-frames, no time-dilation on impact, no dt zeroing. Impact
  weight comes from camera shake + rumble + blood/flash FX + huge reaction anims — never from
  stealing time from the player.
- **ZERO INPUT LAG.** The stick maps STRAIGHT to ground speed every frame. Posture/gait blends
  may smooth the VISUALS only, and only fast (~0.1 s max).
- **WABI-SABI is the house style for ALL art.** Nothing organic is machined: uneven sizes,
  asymmetry, leans, gaps, the odd broken or oversized piece. Author the variation IN with a
  seeded `mathx.Rng` (builds stay deterministic) instead of clean rows or mirrored pairs. When a
  model or anim reads "dumb"/fake it is almost always too REGULAR. Cosmetic only — mechanics
  stay exact (the roll's body is imperfect, its distance/heading/timing identical every time).
- **REACTIONS ARE HUGE.** A flinch or stagger must be big and obvious, never a subtle lean.
- **FLESH IS ROUND.** Organic mass = `addBlob`/`addCapsule`; `addCube`/`addBox` is for iron,
  blades, cloth, masonry. A bare `addCylinder` leaves an open cut-pipe end and a hard rim, and
  those rims + boxes are what read as BLOCKY however good the animation on top is.
- **RELIEF IS SUBTLE.** Protruding detail — flutes, bark ridges, bedding bands, coursing, fracture
  shards — exists to BREAK UP a big mass, and it does that with a few centimetres. Stand it further
  off than that and it reads DISHEVELED: strips stuck onto a column, slates hung off a cliff, a wall
  of rubble tipped into a mould. Detail on a curved mass protrudes a few PERCENT of that mass's
  radius, not a tenth: sink the proud primitive most of the way in and let only its edge break the
  surface. Prefer more SIDES on the mass over more relief on top of it (a 9-gon shaft's flats are
  wide enough that anything sitting on one looks glued to it). And judge the stand-off against the
  ASSEMBLED thing, not one mesh — the cliff ring overlaps segments hard, so detail that clears its
  own body by a little clears its neighbour's by a lot. Cut AMPLITUDE, never irregularity: same
  counts, same seeds, same lean. Quieter is not the same as more regular, and "made regular" is the
  opposite failure, not the fix. See `props.zig`'s RELIEF IS SUBTLE block.
- **PACKED STONE HAS A CORE.** A wall laid as a row of blocks is only the FACING; behind it a
  real wall is packed solid. Without a substrate the joints leak sky (or the far side of the
  room) and it reads as loose stones balanced on each other. And overlap the facing well past
  its slot — butted blocks show a seam round every one, like a model kit. `props.courseInto` /
  `courseStack` do both; every coursed prop goes through them.
- **BIG BODIES HINGE AT THE WAIST, LEGS STAY PLANTED.** A swing is the trunk folding over feet
  that don't move. Route lean through SPINE/CHEST and leave the pelvis nearly upright
  (`ogre.PELVIS_SHARE`); lean at the ROOT rotates the legs and reads as lurching. Braces take up
  in the knees, they don't squat.

## What exists

A convincingly **human** hero that walks / runs / sprints / dodge-rolls and swings a sword (R1
light slash / R2 heavy overhead, kinetic-chain sequenced, swept blade hit-capsule), under a
third-person over-the-shoulder camera, in a lit 3D world with cast shadows (warm low sun vs cool
slate sky, cloud deck, haze, vignette, plus point-light torch/brazier/campfire fire). Three foes
hunt him — **gaping toads**, **skeletal archers**, a lone **one-eyed ogre** — with ER lock-on and
a full combat layer: HP + two-tier poise/stance stagger + death, both sides (`combat.zig`, and
**`docs/ELDEN_RING.md`** as the systems reference). **STAMINA IS FULLY LIVE, LOCKOUT INCLUDED** —
an empty bar means no roll, no swing, no sprint (see STAMINA below). No criticals, guarding or
jump yet. The bar for "human" is anatomy + real gaits, not polygon count.

**THE HUD IS ELDEN RING'S**, in ER's three places and nowhere else: HP/FP/stamina bars top-left,
the four-slot equipment CROSS bottom-left, the debug readout top-right (menu >
Debug > Stats). It hides behind the menu and under the YOU DIED card. FP is a full static bar —
there is nothing to spend it on until spells exist.

**THE WORLD IS DATA, AND THE EDITOR OWNS IT.** `worlds/01_fallen_plain.world` is a versioned
text file of authoring OPS (`worldfmt.zig`); `env.materialize` replays it into props. Nothing
about the world is authored in Zig any more — `env.zig` is the loader, `editor.zig` is the
author, and **Menu > Editor** is how you get there.

**THE MAP STORES THE AUTHORING, NOT ITS OUTPUT.** A wood is one `belt` of 260 attempts with a
kind mix and an edge gradient, not 260 coordinates — so the file is ~280 lines you can read in
a diff, and a density dial re-expands it instead of stamping instances. Ops: `at` (one literal
prop), `belt` (rect scatter), `disc` (annulus), `ring`, `line` (broken run), `ivy` (sows on
standing stonework), `edge` (the cliff rim), `cover` (the lattice ground scatter). Plus `zone`
/ `clear` / `runway` / `foe` tables.

- **EVERY GENERATOR OP CARRIES ITS OWN SEED** and gets its own `Rng`. The old code drew every
  op from ONE shared stream, which meant inserting a belt re-rolled every op after it — no edit
  was ever local, and that alone makes a world uneditable. Independent seeds are load-bearing.
- **ORDER IS MEANING.** Ops replay in file order because later ones read what earlier ones
  placed: `ivy` only climbs stone already standing, a belt only rejects water already poured,
  and `cover` needs the solid grid. The properties panel's up/down move an op for this reason.
- **ONE FIELD TABLE DRIVES THE WRITER AND THE PARSER** (`fieldsOf`), walked at comptime in
  table order. Driving it off `std.meta.fields(Op)` instead reads the STRUCT's order and
  silently writes a value in the wrong column. Unknown keys and missing fields are LOAD ERRORS.
- **A MISSING OR BROKEN MAP PANICS** with the file and line. No built-in fallback: quietly
  running a different world hides the fault behind a world nobody authored.
- **PROPS CAN LEAN.** Any op carries `lean` (degrees off plumb) and `leanDir` (which way it falls,
  measured like yaw): exact on an `at`, and a MAXIMUM on a scatter, which rolls each instance its
  own amount and direction so a wood leans every which way instead of as one storm. Steppers live
  in the properties panel. The tilt turns about the prop's GROUND ORIGIN, so the base stays planted
  and the culling sphere (centred there too) is unchanged — and `buildSolids` carries the footprint
  with it, capped at the part's own radius, or you bump into air beside a tipped trunk. Lean 0 draws
  down the original path and consumes NOTHING from the op's rng, so no existing world moved.
- **WATER IS PAINTED, AND ITS COAST IS DERIVED** (Ground layer > **Water**). The map stores one BIT
  per cell — wet or dry, a finer grid than the soil's (`gfx.WATER_N`) — and `env.uploadWater` turns
  that outline into a SIGNED DISTANCE FIELD: 128 is the waterline, above it depth, below it the walk
  back to dry land. One field, three effects, so they cannot disagree: the shader discards the sheet
  outside the shore, ramps shallow→deep inside it, and WETS THE SAND in the band outside. The sheet
  itself is ONE world-spanning quad on the `.water` material — no mesh is built per coastline, which
  is why re-painting a shore is a texture upload and not a rebuild. `inWater` reads the same field,
  so the flora scatter keeps out of a lake you just painted (a water stroke re-sows on RELEASE).
  The authored `water` PROP still works and is still what the shipped tarn uses.
- **`buildSolids` RESETS.** `materialize` runs it twice (once for the cover scatter to query,
  once after) and an appending version silently doubles every collider in the world.
- Props carry the index of the op that placed them, which is what lets a click on a rock select
  the generator that grew it. Without it only literals would be selectable.
- `bake.zig` is the one-way door that produced the first map from the old code-authored
  regions, kept as the record of where it came from. `--bake` re-runs it and OVERWRITES the map.

**THE WORLD** is a 320 m square golden-hour plain ringed by cliffs, holding five regions
(see the map file, `props.zig` for the models):

| Direction | Region | What's there |
| --- | --- | --- |
| centre / south | the fallen avenue | colonnade, gate arch, grace ember, the start |
| north | **the Fallen City** | plaza, walls, ruined house shells, a torchlit **chapel you walk into**, two **watchtowers** with dark ground rooms, carts, the colossal horizon gate |
| east | **the Tarn** | a shallow lake you **wade**, drowned columns, a collapsed causeway, willows, reeds |
| west | **the Old Wood** | great trees (3 variants), ferns/brambles/bushes, boulders, a **standing-stone circle**, a woodcutter's **cottage** + campfire |
| south | **the Windswept Downs** | open and sparse — lone trees, field stones, graves, a watchtower |

**80 prop kinds**, **17,292 instances and 1,836 colliders**, of which a frame draws **~975** across
both passes (measured in the city; the wood is comparable). See **PERFORMANCE** — that ratio is why
the world is affordable, and the debug Stats overlay prints it live so it stays checkable. The three
numbers are also PINNED by `env`'s "replaying the SHIPPED map produces a stable world" test, so a
scatter that quietly gains or loses instances fails the build instead of drifting in a screenshot.

**Density VARIES, and that is the point** (owner's law). A flat per-region density gives every
square metre the same cover and the result is a carpet — uniformly thick, nowhere to walk,
nothing to notice. `env.coverField` is two octaves of value noise (~34 m clearings broken up at
~11 m) pushed toward its extremes; the region constant is now the PEAK and the field scales it,
to nothing in the clearings. The SAME field gates the scattered structure belts, so a clearing
is a clearing for everything standing in it.

**A region needs three layers to read as lush**, and leaving one out reads as sparse however
many props you place: a GROUND-HUGGER between the standing plants (clover / moss / heather), an
UNDERSTOREY at knee-to-chest height (fern, bramble, thicket, sapling), and the CANOPY. Dead
growth (bracken, snags, stumps, logs) is what stops it looking like a garden. And the SOIL
changes with the region too — the wood's floor is a different colour, not a green tint over the
meadow's (`gfx.terrainAlbedo`'s region drift).

## Build & verify

- `zig` is NOT on PATH. Build with `build.cmd` / `build-release.cmd`; the vendored toolchain is
  `..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe`. `zig build test` runs unit tests.
- Verify rendering/animation changes by RUNNING `zig-out\bin\zig-soulslike.exe --shot` (or
  `shot.cmd`) and INSPECTING the PNGs in `shots\`. `--shot` hides the window: it scripts a walk→
  run→sprint and a roll at several angles, then every foe's states, then the **WORLD TOUR**
  (`70..92`): one framing per region, the chapel/watchtower interiors under torchlight, the tarn,
  the cliffs, five overhead MAP shots and two Stats readouts, then the EDITOR (`95..99e`) — layers,
  a marquee, the ground brush, PAINTED WATER from low down and overhead, and the OBJECT VIEWER's two
  levels. Never claim a visual change works without a shot. `shots\` is gitignored. Do NOT launch the
  interactive window to "check" — the owner plays the real game himself, and while he has it open the
  build cannot overwrite the exe (build with `--prefix zig-out-dev` when it is).
- `--shot-props` renders every kind ALONE into `shots\props\` — one portrait per model, framed off its
  own INFO bounds with the hero beside it for scale. Still the way to sweep the whole set in one go;
  for ONE model the editor's object viewer is faster and shows the same thing from any angle.
- **Framing is part of the test.** Confirm the camera actually SHOWS the moving part before
  tuning from a shot; a mis-framed angle means you're tuning a swing you can't see. Suspect the
  CAMERA first (yaw/pitch/dist) and capture the TRUE contact frame. Landscape shots have three
  traps: `follow` does not clamp pitch, so a small NEGATIVE pitch at long `dist` puts the camera
  under the terrain; the camera ends at `target + back*dist`, so an interior framing must be
  DERIVED from the room's real extent; and the shadow ortho box tracks the HERO, so `standHero`
  near your subject or the shot has no cast shadows. For a WORLD change take a steep overhead
  MAP shot (`dist` near 55 — a camera 85 m up looks through 85 m of haze).
- **Thin geometry needs a CROP.** Strings, nocked arrows, flutes and setts are invisible in a
  full-frame shot; crop and zoom (System.Drawing) before calling one broken. The HUD counts:
  a 34 px slot and a 1 px bar rim are unjudgeable at 1:1.
- **The harness CLOSES THE MENU first** (`runShots`). The menu opens at launch and the HUD hides
  behind it, so without that line every capture is of the game sitting in its pause screen.
  `37_hp_bars.png` is the HUD's own test: it wounds the hero and spends the pool on purpose, so
  all three bars and the chip trail are non-full in exactly one shot.
- `--shot` PNGs are not byte-deterministic (flora wind + grain read `rl.getTime`) — verify
  visually, never by hash-diff.
- Don't commit, push, or create branches unless explicitly asked.

## Module map

- `main.zig`   — entry; `--shot` = headless screenshot harness.
- `game.zig`   — window/loop, input, camera-relative movement + facing, roll trigger, render
                 orchestration (sun depth pass → retro capture → lit pass → filter blit →
                 vignette/HUD/menu), sky, HUD, combat-beat feedback (rumble + shake + hit flash;
                 NO hitstop), the YOU DIED card, and the `--shot` harness.
- `menu.zig`   — the pause/debug menu (OPEN AT LAUNCH: Continue / Debug / Quit). Debug holds
                 Stats / Wireframe / Time Scale and the Retro Filters list (15 filters + presets).
- `hero.zig`   — THE HERO. Anthropometric FK skeleton + every animation, the swept blade hit
                 capsule (rides the SWORD bone's dummy points, active only in the strike's window,
                 FAT on purpose for vertical forgiveness) and the swing trail. The light slash is a
                 REAL cut — the horizontal pair (sabre Cuts III/IV), LEVEL and OUTWARD for the
                 whole hit window (never a dirt-stab, never hilt-first). Start here.
- `camera.zig` — over-the-shoulder orbit rig (yaw + clamped pitch, zoom, shoulder offset,
                 `recenter`), the camera-relative ground basis, trauma-based impact shake
                 (live-loop only, so `--shot` stays deterministic).
- `gfx.zig`    — the mesh `Builder` (boxes plus ROUNDED `addCapsule`/`addBlob`/`addDome`, all
                 revolved about the shared `axisFrame` with ONE continuous UV band). Scene shader:
                 warm hard sun + cast shadows + hemisphere ambient + rim light + POINT LIGHTS +
                 a WATER material + haze + gamma/dither + a wind term + `hitFlash` + SURFACE
                 MATERIALS (every mesh carries surface-anchored UVs and a `gfx.Mat` id;
                 `matAlbedo` textures it procedurally, value-only, ±20%, so nothing reads gaudy).
                 Also the shadow depth pass, the fullscreen `Sky`, and the `Vignette`.
- `worldfmt.zig` — THE MAP FORMAT: the op vocabulary, the zone/clearing/runway/foe tables, and
                 one comptime field table driving both the writer and the parser. Load/save.
- `editor.zig` — THE EDITOR (Menu > Editor). Organised in LAYERS the StarEdit way — GROUND
                 (paint the soil), COVER (zone density + clearings), DECOR (flora), PROPS
                 (stone/timber/fire), UNITS (foe spawns) — and **only the ACTIVE layer is
                 live**: every layer stays visible but a click can only pick, place or erase in
                 the one you are on, so dressing ferns can never nudge a chapel. Each layer
                 ends in its own scoped ERASE brush and remembers the brush you left it on.
                 SELECTION IS BY CLICKING THE THING IN THE WORLD — there is deliberately no list
                 of ops (that was the document model showing through the window, and it read as a
                 history log next to Undo/Redo). A properties
                 panel per op kind, world gizmos, minimap, whole-map undo/redo,
                 New/Open/Save/Save-As (an unsaved map always confirms first), SHIFT+DRAG
                 marquee, drag-the-selection-to-move, Ctrl+C/X/V/A, F5 playtest.
                 **CONTROLS ARE THE OWNER'S, VERBATIM — do not invent additions:** LMB click
                 picks an object, LMB drag PANS; RMB click on an object opens its menu, on
                 nothing DESELECTS, RMB drag ROTATES (4 px splits click from drag); wheel ZOOMS;
                 WASD and the arrows pan; Enter confirms, Esc backs out one level and opens the
                 menu when there is nothing left to back out of. The camera is an ORBIT rig
                 (ground focus + yaw/pitch/dist), not a free-fly, and the pan works by re-aiming
                 at the point the cursor GRABBED — so terrain stays under the pointer at any
                 zoom or angle. THE CURSOR IS SHOWN here and re-hidden on the way out; gameplay
                 hides it because there the mouse IS the camera.
                 SELECT MODE exists because "click to select" and "click to paint" cannot share
                 the left button: it is armed by default, any brush disarms it, Esc re-arms it.
                 Tab cycles layers, 1-9 pick a brush, [ ] size it, G snaps.
                 The CLIPBOARD is file-scope and outlives a map load on purpose, so a stand of
                 trees can be carried from one map into another; its contents are stored
                 relative to the selection's centre, so a paste lands under the cursor.
                 It draws with the RETRO PASS BYPASSED and in a real SYSTEM MONOSPACE face
                 (Consolas, then the other stock fixed-pitch faces — `hud.mono`, NOT Balthazar,
                 and NOT raylib's bitmap font): you cannot dress a world through a lens that is
                 lying about it, and columns of numbers need fixed advances.
                 Chrome text FITS ITSELF to the space left over — the status readout is laid out
                 first and the control crib shortens, then drops, rather than drawing over it.
- `objview.zig` — THE OBJECT VIEWER (editor top bar > **Objects**, or right-click a selection >
                 **View {prop}…**, or the properties panel's **view**). A paged GALLERY of every
                 placeable kind, SHELVED BY LAYER (Decor = the flora palette, Props = the rest, off
                 the same two comptime lists in props.zig), each cell a LIVE off-screen render of the
                 real model through the real scene shader — never an icon, so a mesh that reads wrong
                 here reads wrong in the game. Drag a cell to spin it, wheel to zoom, click to open
                 ONE object filling the screen with its INFO row beside it (bound / top / view /
                 casts / colliders / surface — half of "why does this prop look wrong" is a row in
                 INFO disagreeing with the mesh). Two levels, and Esc backs out one at a time. The
                 preview runs no depth pass, so it calls `gfx.Scene.shadowsOff` — without it every
                 fragment is tested against the WORLD's shadow map and the model comes back dark.
                 It replaces `--shot-props` as the way to judge a model: same look, no rebuild.
- `ui.zig`     — the editor's immediate-mode widget kit, lifted from `../zig-diablo/src/ui.zig`
                 and re-backed onto `hud.zig`. `Ctx.anyHot` gates world clicks NEXT frame.
- `bake.zig`   — the one-way door that emitted the first map from the old code-authored regions.
- `env.zig`    — THE WORLD: the ground plane, the REPLAY of a map's ops into props, the
                 `coverField`, and the three systems that make this size affordable —
                 the UNIFORM GRID, the CULLERS (`View`/`Cull`), the grid-local solid queries.
                 Also gathers each fire's `gfx.Light` and uploads the nearest per frame.
**HOW THE FILES ARE DIVIDED** (and why, because the rule is not "keep files short"): the thing being
minimised is HOW MANY TOKENS IT TAKES TO MAKE A CORRECT CHANGE. That favours COHESION, not size — a
900-line file whose contents all change together is fine, and splitting it into forty files makes the
work harder, because then finding the code costs more than reading it. So the splits here are on
lines where the concerns genuinely part company, and each new file is named so the first grep lands:
- `props.zig` is the VOCABULARY and the TABLE (kinds, groups, INFO, `info()`); the meshes live in
  seven `prop*.zig` files by family — `propart.zig` (the palette + shared weathering moves),
  `propruins`, `propbuild`, `propvillage`, `proprock`, `propwood`, `propflora`, `propfx`. The
  qualifier in each row (`.build = wood.snagMesh`) IS the pointer to the file. Bark reads pale? That
  is one file, and it is the file holding every other thing made of wood.
- `shaders.zig` is every line of GLSL and nothing else; `gfx.zig` is the Zig that compiles it, feeds
  it uniforms and binds it. The contract between them (uniform names, material ids, texture slots) is
  written at the top of `shaders.zig`.
- `shots.zig` is the headless `--shot` harness — ~1,000 lines that never run while anybody is
  playing, and so never belong in context while working on the loop.
- `objview.zig` is the editor's object viewer. `editor.zig` is still the biggest file in the repo and
  is the next candidate (its chrome — top bar, side panel, properties, minimap, status — parts
  company with its editing model), but it has not been split yet.

- `props.zig`  — also `displayName`/`group` for the editor palette: enum tags are terse
                 identifiers ("tree", "birch", "broken") which are right in code and useless in a
                 palette. Both are EXHAUSTIVE SWITCHES, so a new kind is a compile error until it
                 has been named and shelved — same guarantee INFO's comptime block gives, with no
                 second table to keep in lockstep.
- `props.zig`  — EVERY static model, plus ONE table (`INFO`) holding all the rest of the engine
                 needs per kind: mesh builder, bounding radius, top height, view distance, casts /
                 sways, footprint colliders, any fire. A kind is ONE ROW; the old layout spread
                 that across four places and forgetting one failed SILENTLY. Shared weathering
                 helpers (`courseInto`, `courseStack`, `quoinsInto`, `lichenInto`, `chipsInto`,
                 `crackInto`, `tuftInto`) so every ruin ages the same way. Big props with many
                 instances come in VARIANTS (`BIG_TREES`, `CLIFFS`).
- `frog.zig`   — THE GAPING TOAD + the `Knot`. Squash-&-stretch rig, hop/lunge/chomp AI, huge
                 reactions, death → a grace-gold mote DISSIPATION (never a hard vanish).
- `archer.zig` — THE SKELETAL ARCHER + the `Line`. A bare-bones humanoid FOUNDED ON THE HERO RIG.
                 KITE-only AI (holds a range band, never melees) plus one panic **BACKSTEP** on a
                 long cooldown — see below. Slowish arrows that STICK and fade; their homing is a
                 LAUNCH NUDGE that fades out over `ARROW_HOME_FADE`, so a sidestep beats a shot.
                 Arrows are a pool owned by `game.zig` and they respect COVER (each flight-steps
                 against `env.solids()`, thunking into stone while still arcing over low kerbs).
- `ogre.zig`   — THE ONE-EYED OGRE + the `Grief`. A giant (~2x hero), hunched, hefting a knotted
                 CLUB, one dull-amber eye. FOUNDED ON THE HERO RIG but grown to 24 bones (a hinged
                 JAW, TOES, a HUMP, a shoulder GIRDLE); three are inserted ABOVE existing bones, so
                 `poseUpper` sets bones in DEPENDENCY order, not index order. HIGH POISE + two
                 attacks: the OVERHEAD SLAM (long tell → fast crash → long recovery, a crush strip
                 down the facing line) and the FAST SIDE SWIPE (a horizontal scythe through a
                 sector he keeps pivoting into). **HE DOES NOT STRAFE** (`latB` pinned to 0) — he
                 answers a flanking hero by PIVOTING. **THE CLUB NEVER TOUCHES THE GROUND while
                 carried.** Every hurt shape is MEASURED off the posed club (`clubLowWorld()`),
                 never guessed, and unit tests re-assert them — retune anything and RE-MEASURE.
- `foe.zig`    — THE FOE STANDARD: the shared contract + behaviours every enemy plugs into, so
                 lock-on, HP bars, collision, the blade hit-test and the combat beats are written
                 ONCE. Holds `Blade` and `strike()`, the telegraph PARTICLE pool (plus the two burst
                 colours that are the WORLD's and not one creature's — `DUST` and the grace-gold
                 `MOTE` every corpse dissipates into), and the Group plumbing: `resetGroup` /
                 `drawGroup` / `anyDied` / `totalHits` / `runesDropped` / `aliveCount`.
- `combat.zig` — SHARED `Vitals`: HP + the two-tier stagger + regen + death. Plus `Stamina`,
                 the HERO'S ALONE (a foe meter nothing reads would only rot). Pure logic,
                 unit-tested. THE place to retune damage/poise/stamina feel.
- `collision.zig` — 2D XZ capsule/circle footprint collision (push-out).
- `mathx.zig`  — ground-plane + vector/angle helpers.
- `audio.zig`  — THE SOUND BANK: ~40 voices, every one SYNTHESIZED at launch from the same handful of
                 layers (`body` / `air` / `grit` / `ring` / `tick` / `growl` / `chirp`) through one
                 shared tape-style `master`, which is what makes separately-authored sounds feel
                 recorded in the same room. Read it as recipes. Three things to know before retuning:
                 **`master` NORMALIZES each voice** (`norm`), so a layer's `amp` sets its BALANCE
                 inside the voice and only `BANK.gain` sets how loud the thing is; **`vars`/`jit`/
                 `vjit`** are the anti-grate dials (different takes, then pitch, then level); and a
                 voice's shape is judged by EAR — the tests only prove it renders, stays in range and
                 is not silence. An arrow's impact is chosen by the SURFACE it struck
                 (`arrowImpact`): masonry and iron ring, flesh, earth and timber must not.
- `hud.zig`    — UI text in Balthazar; the ONLY path to draw/measure text. Two atlases of the
                 same face: 96 px for HUD, 160 px for the YOU DIED card. Also THE ELDEN RING
                 HUD itself — the three vitals bars and the four-slot equipment cross — taking plain
                 fractions, so it knows nothing about the hero. Colours here are LITERAL screen
                 values (drawn after the retro blit, outside the scene shader), so the
                 author-dark rules do not apply.

## The hero rig (`hero.zig`)

- **Anatomy is real.** Bone lengths are fixed fractions of stature `H` (=1.8) from Drillis &
  Contini (1966) as tabulated in Winter. This is why proportions read as human.
- **Forward kinematics.** 17 bones; `pose()` chains a world matrix per bone ONCE per frame,
  `draw()` only replays them, so the cast shadow and the lit silhouette always match.
- **Matrix convention (critical):** raylib `MatrixMultiply(a, b)` applies **a FIRST, then b**.
  Local = `mul(animRot, translate(offset))`; world = `mul(local, parentWorld)`. Backwards and the
  skeleton explodes.
- **Gaits are real.** Walk uses normative sagittal curves (Perry / Winter); run/sprint use
  Novacheck. Phase is driven by DISTANCE travelled (never time) so feet never skate, and stride
  LENGTH scales with speed so one leg-cycle reads at every pace.
- **THE CROSSING SIDESTEP IS GEOMETRY, NOT TUNED ANGLES.** Both legs take ONE symmetric
  ±`STRAFE_ABD` sweep half a cycle apart; because each hip sits `hx` off the midline the far leg
  lands PAST the near foot. No lead/trail amplitude split. Three rules keep it honest:
  - **A PLANTED FOOT IS WORLD-FIXED.** Through stance its offset from the pelvis sweeps backward
    LINEAR IN DISTANCE. Holding a constant joint angle is only still in JOINT space, and that
    skate — not the amplitude — is what made the old sidestep slide.
  - **ASK FOR FOOT HEIGHTS, SOLVE FOR THE KNEE.** Hip and knee flexion fight each other
    vertically, so a "knee lift" angle does not lift a foot. `legChain` measures the hip's real
    height and solves the knee to place the ankle.
  - **CADENCE has one dial.** Step rate = speed / `STRAFE_CYCLE`. Slow a too-fast sidestep by
    lengthening the cycle or slowing lateral travel — never by pacing the animation.
- **FEET DO NOT SINK: level the ANKLE, never lift the BODY.** `legChain` poses the foot, measures
  its deepest sole corner against its rig's `SolePatch`, and rotates the ankle just enough to
  clear. Two whole-body fixes were tried and REVERTED: lifting the skeleton judders (which corner
  is deepest changes frame to frame) and holding the pelvis up cancels `RUN_CROUCH`. Whole-body
  corrections to a local problem always read as a tremor. Also check the MESH: `addCube` takes a
  FULL size but `addCapsule`/`addBlob` take true RADII.
- **HUMANOID ENEMIES REUSE THE HERO'S WALK/STRAFE.** Any humanoid foe locomotes on
  `hero.advanceGait` + `hero.legChain`. Do NOT author a bespoke walk. Only the upper body /
  weapon is per-enemy. `legChain` is rig-size agnostic, so a foe rig may carry MORE bones than the
  hero's 18 — but it must keep the hero's own leg indices (5..10) where they are.
- **AND THE UPPER BODY MUST ARTICULATE TOO — legs alone are not a gait.** Shared legs under a
  rigid trunk reads as moving in ONE PIECE. Every walking humanoid owes: a contralateral arm
  swing at full amplitude, elbows flexing through the FORWARD half only, a shoulder girdle
  COUNTER-ROTATING against the pelvis (`prot`), a trunk NOD twice a stride, and a head that
  counter-rolls/-yaws/-nods all of it. **And stagger the LAGS** — a loaded limb arrives late and
  whatever it carries later still. Joints that peak on the same frame read as one welded block
  however big the amplitudes. `ogre.poseUpper` is the worked example.
- **A SCALE≠1 humanoid must scale its pelvis HEIGHT** (`pelvY*fs`) or the legs sink and it reads
  as a crouching blob.

### Animation art direction (the DESIRED look)

- **IDLE** — upright, still, alive: a slow breathing bob only.
- **WALK** — unhurried, grounded, near-upright (~3° lean). RESTRAINED arms (never both forearms
  out front — the "zombie arms" fail). LOW hip sway. Clear heel→toe stride, slight toe-out.
- **RUN** — low and aggressive: deep forward lean over a crouched pelvis so the COG leads the
  base. NORMAL pumping arms bent ~90°, explicitly not swept-back "naruto" arms. Real flight phase.
- **SPRINT** — the run dialled up: deeper tilt, lower, longer, faster. Falling forward and
  catching it.
- **ROLL** — three beats: dive into a tight tuck, ONE somersault over ONE shoulder about a low
  ball centre (banked, limbs uneven, drifting roll to roll — cosmetic only), then a spin-free
  rise. Duration/distance/heading exact every time. No float.

Blends: idle↔walk by a `moving` ease; walk↔run↔sprint by ground SPEED. Pose discontinuities
cross-fade ~0.09 s; stances never snap while mechanics stay instant.

## Adding a foe (`foe.zig`)

- **Satisfy the contract.** Expose `pos` + an embedded `combat.Vitals` (`vit`) + `hits` +
  `justDied`, and the accessors `alive/dying/staggered/airborne/bodyR/hurtRadius/centerWorld/
  lockPoint/topWorld/flashFrac` + `tryHit(foe.Blade)`.
- **Reuse the behaviour.** `tryHit` is `if (foe.strike(...)) |s| { own FX; react on s.reaction }`
  — the swept test, one-hit LATCH and damage live in `foe.strike`.
- **Build vitals with `combat.Vitals.initFoe`,** never `init` — that is what puts the enemy on
  the slow foe regen schedule.
- **`justDied` is a ONE-FRAME flag.** Reset it at the TOP of `update`, set it in `enterDeath`,
  and apply the blade at the END of `update`. Applying the blade externally WITHOUT the reset
  latches it on → a nonstop rumble/shake until you quit. Mirror the frog exactly.
- **Humanoids reuse the hero's walk/strafe** (see the rig rules). Never author a second walk.
- **Group + register.** Wrap instances in a `Group` (`Knot`/`Line`/`Grief`) exposing `anyDied` /
  `totalHits` / `aliveCount`; game.zig iterates groups generically. Its `reset` and `draw` are
  ONE-LINE DELEGATES to `foe.resetGroup` / `foe.drawGroup` — don't re-write either body. The draw's
  `setFlash(0)` tail is the line a fourth copy would forget, and a Group that leaves the uniform hot
  reddens whatever draws next.

## Combat feel

- **The two sides are tuned SEPARATELY** (`combat.zig`). A stagger you inflict is a punish WINDOW
  you must be able to walk into and use; a stagger you suffer is time taken off the player, which
  the FEEL RULES spend as little of as possible. Hence `FOE_LIGHT_STUN_DUR` / `FOE_HEAVY_STUN_DUR`
  well past the hero's, and `FOE_REGEN_DELAY` / `FOE_REGEN_RATE` far slower — a foe whose poise is
  back before your next swing can only be staggered by a burst, and every fight collapses into
  "land two fast or don't bother".

## STAMINA (`combat.zig`) — the soulslike rules, all of them

- **AN EMPTY BAR LOCKS OUT roll / attack / sprint** (`STAM_LOCKOUT`, owner's call). This does NOT
  break the no-time-theft law: that law forbids taking control away during the player's own
  action, and a lockout is the consequence of a choice made a second earlier, readable off a bar.
- **WALKING IS NEVER GATED.** Running dry drops you to a walk (`mv.speed` is capped to
  `RUN_SPEED`), never roots you. Denied at the SOURCE so `sprintingMove` stays the one definition
  of a sprint and the speed, the facing exceptions and the bleed cannot disagree.
- **YOU MAY ACT ON ANY STAMINA ABOVE ZERO** — `canAct()` is `cur > 0`, NOT `cur >= cost`. A roll
  costs 12 and you can take it on 1, emptying the bar and locking you out after. That asymmetry
  is the PANIC ROLL, and gating on the cost instead deletes the genre's most important move and
  turns the bottom tenth of the bar into decoration. Every FromSoft game works this way.
- **A COMMITTED ACTION IS NEVER CUT SHORT.** `spend` floors at 0; nothing is refunded or aborted
  partway by the pool running out.
- **THE REFILL PAUSES while attacking, ROLLING or sprinting**, then waits `STAM_DELAY`. Rolling
  counts, or a roll chain costs less than the sum of its rolls.
- **A REFUSED ACTION IS SHOWN** (`hero.stamRefused` → a red ring on the stamina bar). In ER an
  empty-bar input does nothing at all, and *nothing* is indistinguishable from a dropped input —
  which under a ZERO INPUT LAG law is the one thing the player must never have to wonder about.
  Feedback only; it changes no mechanics.
- **The shot harness stages its own stamina** (`stagedAttack`/`stagedRoll` reset the pool). It
  photographs animations, not the economy — seven attack shots back to back would otherwise
  drain the bar and the last ones would silently become pictures of a hero standing still.

## Foe pacing

- **The archer's BACKSTEP** is a committed jump straight back, triggered inside sword reach, on a
  long (7 s) cooldown. Its walking kite is a stroll and a hero who simply runs at it would always
  be on top of it; this buys the shot back exactly once, and closing the distance stays the
  correct answer the rest of the time. An evade you can spam is a wall.

## Controls (`game.zig`)

Keyboard+mouse OR gamepad; the pad follows **Elden Ring's default layout** (**ER** = the
north-star reference throughout this file).

**WALK vs RUN (owner's definition):** the whole left-stick range is **WALK** (tilt scales walk
speed only), and **RUN is exclusively the hold-B / hold-Shift sprint**. So stick-only movement
even at full tilt reads as a walk, and the aggressive "run" presentation (the out-to-the-side
sword carry, the deep lean) belongs to the hold-B RUN only — gate run-only flourishes on
`sprintB`, not the stick-speed `runB`.

- **Mouse:** HIDDEN over the window and drives the camera, but NEVER locked/captured. Push it
  past the window edge and it reappears as a normal OS cursor. Deliberate — the owner needs the
  mouse outside the game; do NOT reintroduce `disableCursor`/pointer-lock.
- **Move:** WASD / left stick, camera-relative; the hero turns to face travel. **Sprint:** hold
  Shift / Circle-B. **Dodge roll:** Space / TAP Circle-B (tap-vs-hold on the same button, like
  ER). **Attacks:** R1/RB or LMB = light slash; R2/RT or Shift+LMB = heavy overhead. Actions are
  committed (no mid-swing cancels) with an **ER-style input queue**: pressed mid-action, an
  attack/roll buffers in ONE slot (last press wins; a same-frame roll press outranks attack) and
  fires at the earliest exit — the attack's chain knot or the roll's end. A queued roll leaves in
  the direction HELD at fire time, not pressed.
- **Camera:** mouse / right stick; scroll or D-pad zoom. **Esc** opens/backs out of the menu (pad
  **Start** toggles). Quitting is a menu row. The menu opens at launch; while it's up gameplay
  input is held and the world idles.
- **Lock-on (ER):** **R3** / **middle-mouse** toggles onto the foe nearest screen-centre; with
  none available R3 recenters. While locked the camera swings on, the hero faces it with REAL
  strafe/backpedal footing, a glowing white dot marks it, and a stick/mouse **flick** cycles
  targets. Two deliberate ER exceptions: a hold-B SPRINT while locked faces TRAVEL (no sideways
  sprint exists), and an attack's recovery tail re-squares onto the target (`ATK_RETRACK`).
- Reserved, matching ER: Cross/A = jump, L1/L2 = guard/skill.

## PERFORMANCE: how a 320 m world stays cheap (`env.zig`)

Four things carry it; all four are load-bearing.

- **UNIFORM GRID (CSR).** Props bucketed by 16 m cell into two indexes — structures and flora —
  built by counting sort into one flat array. No allocation, no pointers, and each cell carries
  the MAXIMA its pass needs so a whole cell can be accepted or rejected before any prop in it is
  looked at.
- **THE LIT PASS culls per cell, then per prop**: four frustum SIDE planes plus each kind's own
  `view` distance (stricter and cheaper than near/far planes).
- **THE DEPTH PASS culls by SHADOW REACH, not camera distance.** At this sun elevation a caster
  throws its shadow ~1.5x its height sideways (`SUN_REACH`), so a prop matters iff its footprint
  plus that reach can touch the sun's ortho box (`castsInto`). A naive distance cull here clips
  real shadows; this is the version that doesn't.
- **COLLISION + ARROW FLIGHT query the grid**, never the whole solid list.

**Check it, don't trust it.** Menu > Debug > Stats prints `world props N solids N fires N drawn N
in N cells`, and `--shot` captures it (`91_stats_city.png`, `92_stats_wood.png`). If `drawn` ever
approaches `props`, a culler has been defeated.

**Caps are init-time PANICS, not silent drops** (`MAX_PROPS`/`MAX_SOLIDS`/`MAX_SOLID_REFS`). A
silently dropped collider is a walk-through wall and a dropped prop is a hole in the world.
Placement is deterministic: if it fits once it fits.

## Hard invariants & gotchas

- **Coordinates:** ground is XZ, Y up. Hero faces +Z at yaw 0; `atan2(facing.x, facing.z)` is the
  facing angle.
- **Strafe sign:** the camera looks +Z from behind, so screen-right is world −X →
  `camera.rightXZ` MUST be `(−cos yaw, 0, sin yaw)`. Flipping it mirrors L/R walking.
- **VSYNC, not `setTargetFPS`.** `vsync_hint` is set before `initWindow` and there is deliberately
  no frame cap: `setTargetFPS` is a CPU-side limiter that never asks the driver to swap during
  vblank, so the swap lands mid-scan and TEARS in exclusive fullscreen. Two limiters also fight on
  any panel that isn't 60 Hz.
- **Depth z-fighting:** `rlSetClipPlanes(0.2, 320)` at startup — the default 0.01..1000 wrecks
  precision and the hero's overlapping boxes flicker. The ground sits a hair ABOVE y=0
  (`env.GROUND_Y = 0.01`) where soles and prop bases are authored, so content is
  planted-to-slightly-embedded and never FLOATS.
- **Sun + shadows are ONE source** (`gfx.SUN_DIR`) feeding both the shader and the shadow camera.
- **Shadow pass contract:** every caster draws through `game.drawCasters` (used by BOTH passes, so
  transforms can't drift). drawMesh/drawModel use the MATERIAL's shader, so the depth pass swaps
  caster shaders (`setCasterShaders`) and runs BEFORE `beginDrawing`. Terrain receives but does
  not cast, and FLORA is a non-caster too (thin swaying blades would sparkle in / desync from the
  shadow map). The ortho box tracks the hero, snapped to shadow texels so edges don't crawl.
- **The hero is per-bone matrices, not `drawModelEx`.**
- **The scene shader gammas output (`pow 1/2.2`): author dark colours near-black.**
- **Vertex alpha is the EMISSIVE channel** (255 = fully lit; lower = self-lit).
- **A BIG SMOOTH MASS NEEDS A NEARLY-BLACK ALBEDO** — and FORM BREAKS. The shader's hot key
  (`*1.72`) plus the gamma lift turns any mid-dark value pale wherever a large face takes the sun
  square on (`BARK_OLD`, the `CLIFF_*` set, `PAVE*`, the `MARBLE*` set all exist for this). The
  bigger the face, the darker it must start — and a dark smooth mass still reads as plastic
  without breaks (the trunk's bark ridges, a column's flutes, a keep's course banding).
- **TWO STONE MATERIALS.** `.stone` is rubble masonry, matte; `.marble` is the dressed stone of
  the kingdom that fell — veined by the shader and carrying the only real gloss besides steel and
  water. That gloss is what says one of them was built with money, and it is kept LOW: a gloss
  that reads "shiny" on a swatch lays a wash over every sunward face and undoes the dark-albedo
  rule. Marble = columns, arches, statues, entablature; stone = walls, towers, cottages, rubble.
- **`gfx.Mat` is APPEND-ONLY** — the shader hard-codes 9 for water and 10 for marble; comptime
  asserts guard both.
- **BUILDER WINDING IS NOT CHECKED, AND FACE-DOWN GEOMETRY IS INVISIBLE.** A flat annulus swept
  outward-first points DOWN, raylib culls it, and the tarn simply isn't there (the declared `n`
  does not fix the winding). Sweep inner@a0 → inner@a1 → outer@a1 → outer@a0. Likewise `addBox`
  accepts a **non-perpendicular** axis triple and builds a skewed parallelepiped with daylight
  between the blocks. For a ring, radial is the position direction and tangent is
  `(cos a, 0, sin a)`; for an arch ring at angle a, radial is `(−cos a, sin a, 0)` and tangent is
  `(sin a, cos a, 0)`.
- **A cylinder is CAPLESS.** An open end shows its culled interior — you see straight through it.
  Cap with `addDome` (rounded) or an axis-flattened `addBlob` (flat); a flat cap constrains the
  piece to a world axis, which is why the fallen column drums lie along X and Z.
- **REPEATED BIG PROPS NEED VARIANTS.** One mesh placed sixty times across a wood, or every 6.5 m
  around the horizon, reads as a periodic pattern. Yaw and scale do not hide it. `BIG_TREES` /
  `CLIFFS` exist for this, and long-wavelength variation beats per-instance noise.
- **A CULLER BUG LOOKS LIKE AN EMPTY WORLD, AND ONE-ORIENTATION TESTS MISS IT.**
  `View.fromCamera` sign-corrects its plane normals against the camera forward instead of assuming
  a handedness — this camera's screen-right is world −X. Its test sweeps seven headings.
- **A LIGHT'S RADIUS MATTERS MORE THAN ITS BRIGHTNESS.** A 9 m torch in a 5x7 m chapel reaches
  every surface from every corner, so four summed to a flat wash however dim each was. Fire has
  to POOL: small radii, few of them, darkness between.
- **Fullscreen shader passes must build their ray/UV from `gl_FragCoord`** + a resolution uniform
  when drawn via `drawRectangle` — raylib maps rectangle texcoords to the tiny shapes-texture
  rect, so `fragTexCoord` is effectively CONSTANT (the sky hit this). `drawTexturePro` blits are
  fine.
- **Retro pass contract:** when any filter is active the whole frame renders into `Retro.rt` then
  blits through the combined filter shader; vignette, HUD and menu draw AFTER the blit so they
  never crunch. All-zero = pass bypassed entirely.
- **THE RETRO RT IS `GL_NEAREST`, AND PIXELATE POINT-SAMPLES IT.** A block kept one pixel of the
  four and threw the rest away, so fine distant detail twinkled as it moved between a kept and a
  discarded pixel. `sceneTap` box-filters the block instead (`PIX_BOX` is how much of the average
  to take: 0 = hard blocks + the flicker, 1 = a true 2x2 downsample, soft). This is a TRADE, not a
  free win — the twinkle IS a hard edge crossing a pixel boundary. Distance-fading the pixelation
  instead was considered and REJECTED: `loadRenderTexture` attaches depth as a renderbuffer so
  there is nothing to fade against, and block sizes are whole pixels, so at the 2 px default the
  only step down is "off" — a hard ring sliding through the world.
- **SUB-PIXEL FILTER OFFSETS SNAP UNDER NEAREST, AND FILTERING THEM UNDOES THAT.** The chroma
  fringe's offset is half a pixel at its default, which `GL_NEAREST` rounded back onto the base
  texel — with pixelate on the fringe was a near no-op, which is the look it was tuned to. Routed
  through `sceneTap` that same half pixel straddled the block boundary and R/B smeared a whole
  pixel apart: a colour blur that reads as "the box filter made it blurry". Its offset now snaps
  to whole BLOCKS, so every channel reads the same averaged block.
- **All UI text goes through `hud.text/textW`**, in **Balthazar** (`assets/`, OFL alongside;
  owner's pick). The atlas is **ASCII-only** — a `·` or `—` renders as tofu. Exo and Tagesschrift
  are GONE; one face only.
- **SIZES COME FROM `hud`'s TYPE SCALE** (`TITLE`/`BODY`/`SMALL`/`HINT`), never a literal at the
  call site; stacked rows step by `hud.lineH(size)`. Two rules keep it crisp: the atlas resolution
  must stay ABOVE the largest size drawn (an UPSCALED glyph is the jagged one), and the drop
  shadow's offset scales with the size (a fixed 1 px shadow under large type reads as a smudge).
- **Prototype models/meshes are permanent** (CPU arrays stay attached; they live the whole program
  and leak at exit — fine). Don't `unloadModel` them.
- **Never bulk-edit source through PowerShell** `Get-Content`/`Set-Content`: em dashes mojibake
  and a BOM appears. Use the Edit tool.

## Next steps (not yet built)

**Criticals** off a stance break (the stagger already exists), hyper-armor windows during the
hero's own attacks, guarding + **guard counter** — which is also the last piece of stamina ER has
and this doesn't: blocked hits cost stamina by Guard Boost, and emptying the bar while guarding is
a GUARD BREAK. AR × motion-value × defense damage (today it's flat constants), **status buildup**,
jump, distinct combo follow-up anims, bonfires, real level geometry. See `docs/ELDEN_RING.md` for
the target mechanics behind each.

Current gaps: the roll has front-loaded i-frames (0→0.46 s of 0.70 s, gating `takeHit` + the
arrow connect) but still **no collision**; there is **no foot IK** — `rx(bodyPitch)` in
`hero.pose()` rotates the body about the WORLD ORIGIN, not the support foot, so under a deep lean
a forward-swung foot is levered down (walking and pure sidesteps are exact; a diagonal keeps
~6 cm). One leg-cycle is reused across run and sprint, and attacks reuse one anim standing or
moving.
