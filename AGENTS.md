# AGENTS.md — zig-soulslike

A third-person **soulslike** prototype in native **Zig 0.14.1 + raylib**, founded on the sibling
`../zig-rts` rendering engine (procedural-mesh `Builder`, single-sun shadow-map pipeline).

IMPORTANT!!! IMPORTANT!!!
-

Keep this file lean!!! Prefer no comments in code!!! write succinct ones for novel/edge cases ONLY.
Reuse existing helpers before adding new code ALWAYS. Don't make ad-hoc product/design decisions.
ask. The owner drives the design; implement what's asked and nothing extra.

-

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
- **NOTHING DEAD IS STRAIGHT, AND NOTHING ENDS IN A POINT** (owner: the leafless trees' "branches are
  all floating"). A limb drawn as ONE capsule to a needle tip is a SPEAR, and a rosette of them is a
  hub of spokes — which is what read as detached, not the placement. A dead limb leaves the bole on the
  bole's own AXIS, rises to an elbow, then DROOPS and bends off the line to a blunt SNAP of pale
  heartwood; its twigs root on that outer half and carry ON outward. Struck off across the limb instead
  they cross their own parent and read as loose needles lying near a branch. `propwood.deadLimbInto`
  is the one of these both leafless trees (`tree`, `snag`) call.
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
  its slot — butted blocks show a seam round every one, like a model kit. `propart.courseInto` /
  `courseStack` do both; every coursed prop goes through them.
- **BIG BODIES HINGE AT THE WAIST, LEGS STAY PLANTED.** A swing is the trunk folding over feet
  that don't move. Route lean through SPINE/CHEST and leave the pelvis nearly upright
  (`ogre.PELVIS_SHARE`); lean at the ROOT rotates the legs and reads as lurching. Braces take up
  in the knees, they don't squat.

## What exists

A convincingly **human** hero that walks / runs / sprints / dodge-rolls and swings a sword (R1
light slash / R2 heavy overhead, kinetic-chain sequenced, swept blade hit-capsule), under a
third-person over-the-shoulder camera, in a lit 3D world with cast shadows (warm low sun vs cool
slate sky, cloud deck, haze, vignette, plus point-light torch/brazier/campfire fire). Four foes
hunt him — **gaping toads**, **skeletal archers**, **skeletal WARRIORS** (`warrior.zig` — a shieldman who
BLOCKS you until you break his guard and a greatsword with an uninterruptible diagonal slam), a lone
**one-eyed ogre**, and a **kobold WARBAND**
(`kobold.zig` — three roles of one doglike creature in ONE group, because the priest heals its
friends: berserker / priest / slinger) and a **BROOD MOTHER** with her egg sacs and **BROODLINGS**
(`brood.zig` — a slow, claw-armed spider who spits ACID POOLS to hold you off a clutch she keeps
laying; the sacs are killable and each hatches one fast hatchling if they are not) — with ER lock-on and
a full combat layer: HP + two-tier poise/stance stagger + death, both sides (`combat.zig`, and
**`docs/ELDEN_RING.md`** as the systems reference). **STAMINA IS FULLY LIVE, LOCKOUT INCLUDED** —
an empty bar means no roll, no swing, no sprint (see STAMINA below). He carries a **SMALL ROUND
SHIELD** in the left hand and **GUARDS** with it — Dark Souls' plain block, paid for in stamina,
with a GUARD BREAK when the bar runs out under a blow (see GUARDING). His right hand also holds a
**BOW** (D-pad Right swaps to it — quick shot on R1, hold L2 to aim and R2 to loose), and because the
left hand goes to the string it takes the shield with it (see THE BOW) — with a scarce **FIRE ARROW** on
D-pad Up that is the game's one source of non-physical damage, against four PoE2 **RESISTANCES** every
creature carries (see RESISTANCES). No criticals, guard counter or jump yet. The bar for "human" is anatomy + real gaits, not polygon count.

**THE GROUND HAS ELEVATION**, sculpted in the editor and walked with a real slope limit and a step
height — hills, banks, terraces and cliffs you cannot climb (see ELEVATION). The SHIPPED map is
deliberately flat, and a flat map is byte-for-byte the world that existed before it.

**THE HUD IS ELDEN RING'S**, in ER's three places and nowhere else: HP/FP/stamina bars top-left,
the four-slot equipment CROSS bottom-left, the debug readout top-right (menu >
Debug > Stats). It hides behind the menu and under the YOU DIED card. FP is a full static bar —
there is nothing to spend it on until spells exist. The cross's two hand slots draw **WHAT IS IN HIS
HANDS**, not what he owns: RIGHT is the sword or the bow, LEFT is the small shield or — behind a bow —
EMPTY, which is exactly what the bow costs him. UP (sorcery) stays empty too, because an empty ER slot
is a real part of that HUD and inventing something to put in it would be a lie in the corner of every
screenshot. Four slots, and it stays four however many armaments exist.

**A CHEST IS HOLLOW.** Its carcase was one solid cube, so throwing the lid back revealed a sealed
timber top — you opened a box and found a block. Four walls and a floor now, with the outer faces
exactly where the solid mass's were. And the lid's BELLY is the face you actually look at once it is
open (the dome and both iron straps are pointing away by then): it is the drum's lower arc, dressed
with dark lining boards and light battens. A flat lining panel under the slab was tried first and was
invisible — this lid is a CLOSED cylinder and the slab lives inside it.

**THE WORLD IS DATA, AND THE EDITOR OWNS IT.** `worlds/01_fallen_plain.world` is a versioned
text file of authoring OPS (`worldfmt.zig`); `env.materialize` replays it into props. Nothing
about the world is authored in Zig any more — `env.zig` is the loader, `editor.zig` is the
author, and **Menu > Editor** is how you get there.

**AND THERE ARE TEST ZONES BESIDE THE SHIPPED MAP.** `02_brood_arena.world` and
`03_bone_court.world` are small walled courts holding ONE fight each, for judging a creature without
walking the plain to find it — the Bone Court posts two skeletal shieldmen and two greatswords, plus
one of each campfire. Reach them the same way: **Menu > Editor > Open**, then **F5** to playtest.
A test zone nobody boots into is a file that rots, so `env`'s "EVERY SHIPPED MAP LOADS AND
MATERIALIZES" test loads and replays all of them — an op renamed under `02`/`03` fails the build
instead of panicking in the Open dialog months later.

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
- **THE GROUND HAS A SHAPE, AND YOU SCULPT IT** (Ground layer > **Raise / Lower / Smooth / Flat**). The
  map stores one QUANTISED HEIGHT per lattice point — `wf.HEIGHT_N` at 2.5 m, `HEIGHT_STEP` 0.25 m,
  biased so the byte `HEIGHT_ZERO` is the old flat ground — and `env.uploadHeight` turns it into the
  terrain you walk on. See ELEVATION below for the whole system; the load-bearing parts:
  - **A FLAT MAP IS THE OLD WORLD, EXACTLY.** `heightAny` false means the terrain is the ONE original
    world-spanning quad, `groundAt` returns `GROUND_Y`, `walkStep` returns the step it was given, and
    the `hgt:` record is not written at all. That is why elevation touched no existing world file and
    why the shipped map is byte-for-byte the plain it always was.
  - **QUANTISED BECAUSE THE FILE IS TEXT.** The writer is a run-length encoder; a float grid is 50,176
    unique values with no runs in it. At 0.25 m a plateau, a bank and a valley floor each collapse to
    one run, and 0.25 m over a 2.5 m cell is 5.7 deg — under the mesh's own faceting.
  - **THE MESH IS TILED** (`TCHUNK`, 15x15 tiles): a sculpt stroke rebuilds the two or three tiles it
    touched instead of 100k triangles, and the tiles are the draw cull unit. Normals come from the
    FIELD, not from each tile's triangles, so two independently-built tiles agree at their seam.
  - **NOTHING SAMPLES THE MAP DIRECTLY.** Env keeps the live copy (`heightField`) that the visible mesh
    was built from, and `wf.sampleHeight` is the ONE sampler both owners call — so the hero cannot walk
    a centimetre off the mesh he can see. A test pins the two together.
  - **EVERY PROP PLANTS AT THE HEIGHT UNDER IT**, which is why `uploadHeight` must run BEFORE
    `materialize` (`env.build` → uploadSoil → uploadWater → uploadHeight → materialize) and why a
    sculpt stroke re-materializes the world on RELEASE, exactly as a water stroke re-sows it.
  - **THE SKIRT** carries the ground from the map's rim out to the haze, its inner edge following the
    border heights so there is no step at the seam.
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

**THE WORLD** is a 560 m square golden-hour plain ringed by cliffs (`worldfmt.DEFAULT_HALF` is 280,
and the map's own `half:` is the only source), holding five regions
(see the map file, `props.zig` for the models):

| Direction | Region | What's there |
| --- | --- | --- |
| centre / south | the fallen avenue | colonnade, gate arch, the bonfire camp, the start |
| north | **the Fallen City** | plaza, walls, ruined house shells, a torchlit **chapel you walk into**, two **watchtowers** with dark ground rooms, carts, the colossal horizon gate |
| east | **the Tarn** | a shallow lake you **wade**, drowned columns, a collapsed causeway, willows, reeds |
| west | **the Old Wood** | great trees (3 variants), ferns/brambles/bushes, boulders, a **standing-stone circle**, a woodcutter's **cottage** + campfire |
| south | **the Windswept Downs** | open and sparse — lone trees, field stones, graves, a watchtower |

**82 prop kinds**, **17,088 instances, 1,801 colliders and 37 fires**, of which a frame draws **768 in
259 cells in the CITY and 1,332 in 312 in the WOOD**, both passes together — read off
`91_stats_city.png` / `92_stats_wood.png`, which is the only honest way to state it. (This said "~633
… the wood is comparable": the figure predates the last two world edits and the wood was never
comparable — it is nearly twice the city, because a wood is canopy standing in front of canopy.)
See **PERFORMANCE** — 7.5% of the world is
why it is affordable, and the debug Stats overlay prints it live so it stays checkable. `env`'s
"replaying the SHIPPED map produces a stable world" test PINS the same three, so a scatter that quietly
gains or loses instances fails the build instead of drifting in a screenshot — but **its prop count is
the HIGHER of the two on purpose** and the two must not be reconciled: the test calls `materialize`
without `uploadWater`, so the painted tarn rejects nothing and it pins **17,202** where the running
game shows 17,088. Solids and fires do not read the water and so match exactly.
**Move both together when either moves**: the props rework left the test pinning 17,292/1,836/34
and this line repeating it, and `9dea3c0`'s world edit left both at 16,884/1,687/35, so the guard sat red
— and the LAST move of it was two changes at once, which is the case to be careful of: five cliffs the
owner added in the editor (+5 props, +10 solids, and the counts added up exactly) and the campfire going
cold in the CODE (−3 fires). Two causes, one red test; read the three numbers separately or you will
"fix" the world for something the engine did
for two commits each time — and a pin that always fails cannot
catch the next drift, which is the only thing it is for. **AND `git diff worlds/` BEFORE SUSPECTING THE
CODE** — the owner edits the map in the editor while playing, so the commonest reason this pin goes red is
that the WORLD changed, not the engine. The three numbers tell you which: a world edit's counts add up
(two cliffs = +4 solids exactly, because `cliffParts` is 2 each, plus the cover their footprints now
reject), where a code fault does not land that neatly.

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
meadow's (`shaders.terrainAlbedo`'s region drift — the GLSL, not the Zig).

## Build & verify

- `zig` is NOT on PATH. Build with `build.cmd` / `build-release.cmd`; the vendored toolchain is
  `..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe`. `zig build test` runs unit tests.
- Verify rendering/animation changes by RUNNING `zig-out\bin\zig-soulslike.exe --shot` (or
  `shot.cmd`) and INSPECTING the PNGs in `shots\`. `--shot` hides the window: it scripts a walk→
  run→sprint and a roll at several angles, the sword swings, the GUARD (`20a..20e` — the stance from
  three bearings, a caught blow mid-recoil, and the shield's own back), the BOW (`20f..20r` — see THE
  BOW), then every foe's states —
  including the kobold POUNCE in three beats (`66d..66f`) and the BITE in profile (`69c`/`69d`), both
  of which shipped unjudged because neither had a shot, and the SKELETAL WARRIORS (`113…` — the pair, the
  shieldman's guard and a crop of his boards, the mace in four beats, the KNEEL with the shield broken off
  him, the diagonal slam and the leaping LUNGE in four each) and the two CAMPFIRES side by side (`114…`)
  — then the **WORLD TOUR**
  (`70..92`): one framing per region, the chapel/watchtower interiors under torchlight, the tarn,
  the cliffs, five overhead MAP shots and two Stats readouts, then the EDITOR (`95..99g`) — layers,
  a marquee, the ground brush, PAINTED WATER from low down and overhead, the OBJECT VIEWER's two
  levels, the INTERACTABLES layer and the JUKEBOX (`99f`/`99g`) — then ELEVATION (`100..105`): a sculpted ridge from below and from on it, the hero having
  WALKED up it (through the real `walkStep` + grounding + lean, with the debug numbers on), its profile
  from a distance, and the Ground layer with a sculpt brush armed. That block sculpts the live map and
  puts it back, so it runs LAST and nothing after it stands on terrain the shipped map does not have.
  Never claim a visual change works without a shot. `shots\` is gitignored. Do NOT launch the
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
- **A SUBJECT MUST BE LIT, NOT JUST IN FRAME.** `gfx.SUN_DIR` is (−0.60, 0.50, −0.46), which in the rig's
  terms means the sun is over the shoulder of a camera at **yaw ≈ 53** and straight into the lens of one at
  **≈ 233**. A foe TURNS TO FACE the hero, so "photograph its front" means putting the sensed hero where the
  camera is — and parking that in the 180-215 band puts its front in its own shadow: near-black, no
  colour, no fur, no weapon, and unjudgeable (every kobold role portrait was shot that way). Put the
  sensed hero on the SUN's bearing and shoot from ~53; for a lit REAR view turn the subject round rather
  than orbiting the camera behind it.
- **Thin geometry needs a CROP.** Strings, nocked arrows, flutes and setts are invisible in a
  full-frame shot; crop and zoom (System.Drawing) before calling one broken. The HUD counts:
  a 34 px slot and a 1 px bar rim are unjudgeable at 1:1.
- **JUDGE ALBEDO BY SAMPLING THE RENDER, NOT BY EYE.** The chain is albedo × the shader's hot key (1.72)
  → linear → gamma 1/2.2, and a 2.2-power curve beats intuition every time: a "dark brown" 46/34/22 pelt
  came back on screen at 151/130/107, i.e. pale khaki, and within 10% of the golden-hour grass beside it in
  BOTH value and hue — so there was no silhouette at all. Four passes of nudging that by feel got nowhere;
  one `GetPixel` of the subject AND of what it stands against settled it. Screen ∝ albedo^(1/2.2), so a
  factor you want on screen is that factor^2.2 on the albedo — solve, don't guess. Separate on HUE as well
  as value: everything outdoors here is warm, so a warm-brown creature needs to be greyer as well as darker.
- **THE SCREENSHOT GOES BEFORE `endDrawing`, NEVER AFTER** (`shots.snap`). `endDrawing` SWAPS the
  buffers and `takeScreenshot` reads the CURRENT one, so taken after the swap every capture is the
  PREVIOUS frame. The whole harness was off by one: `91_stats_city.png` came back with no Stats overlay
  on it and the world tour each held the framing before it. It hid for a long time because consecutive
  shots mostly look alike — it took a hard cut (the object viewer's chrome turning up in a landscape
  shot) to be obvious. Flush the batch first, exactly as raylib's own F12 handler does.
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
- `menu.zig`   — the pause/debug menu (OPEN AT LAUNCH: Continue / Options / Editor / Debug / Quit).
                 OPTIONS holds the three SOUND LEVELS — Ambient / Sound Effects / Combat, one per
                 `sfx.Submix` (`OPT_MIX`, comptime-checked to cover every family, or a voice would be
                 one the player can never move). They PERSIST in `settings.cfg` beside the exe, written
                 when the screen closes rather than per nudge (a held Left glides at frame rate) and
                 read back in `sfx.init`. Debug holds Stats / Wireframe / Time Scale and the Retro
                 Filters list (15 filters + presets). Both slider screens share one gauge column
                 (`drawCard`'s `gauges` slice) and one adjust feel (`adjustDelta`).
                 **START OPENS THE CHARACTER MENU** (Attributes / Resistances / Inventory / Equipment), a second root
                 the whole screen stack hangs off (`Screen.root`) so SELECT and START toggle their own
                 side and nothing else. ATTRIBUTES is the character sheet — the seven of `stats.zig`,
                 rows walked off the enum, each with its points right-aligned and a FOOTNOTE saying what
                 the selected one governs and how much of that bar it is buying. Read-only: there is no
                 leveling, so no row adjusts. One `drawCard` draws every screen and its optional columns
                 are one `Card` struct (`gauges` / `values` / `note`); a column slice SHORTER than the
                 row list simply leaves the tail bare, which is how Back gets no number.
- `hero.zig`   — THE HERO. Anthropometric FK skeleton + every animation, the swept blade hit
                 capsule (rides the SWORD bone's dummy points, active only in the strike's window,
                 FAT on purpose for vertical forgiveness), the swing trail, and the GUARD — the
                 stance, the caught-blow recoil and the small round SHIELD (which is not a bone: it
                 rides the left wrist through `shieldFit`), and THE BOW — the second right-hand
                 armament, in the same `HELD` slot, with the live string and nocked shaft borrowed
                 whole from `archer.zig` (see THE BOW). See GUARDING. The light slash is a
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
                 **FLOORING IS TWO GRIDS, NOT ONE.** `soil` is the material id per cell; `soilCov` is
                 how strongly it covers, 0..255. An edge is NOT a special case — it is simply where the
                 author left the coverage low, which is why one number buys both "fade this margin" and
                 "make this whole patch faint" (owner: "opacity of the edges — or wherever really").
                 THE PAINT RULE is `lerp(here, opacity, falloff)` inside the stroke: painting below what
                 is there THINS it, overlapping strokes don't carve each other, and repeated passes
                 converge on the dial instead of running away. A cell holding a DIFFERENT material is
                 CONTESTED — the stroke wins it only where it would cover more than the incumbent —
                 so a faint pass can't eat a solid floor; the eraser is exempt and clears outright.
                 `BRUSH_CORE` (0.55) keeps the middle solid: a pure cone made "paint at 100%" come out
                 translucent everywhere, because the lattice is 5 m and a small brush is one cell wide.
                 **HARD vs SOFT EDGES ARE A PROPERTY OF THE MATERIAL** (`Soil.hardEdge`, stone only for
                 now), pinned to the shader's `soilHard` by a comptime assert on the enum value. Hard
                 materials snap the coverage uv to the texel centre (point sampling out of a bilinear
                 texture) and skip the shader's structural blend ring — a crisp cell-wide edge, still
                 ragged from the existing jitter, and the authored LEVEL is untouched so hard-edged
                 never means always-opaque. Coverage defaults to `COV_FULL`, so a map written before it
                 existed carries no `soilcov` record and renders exactly as it always did.
- `editor.zig` — THE EDITOR (Menu > Editor). Organised in LAYERS the StarEdit way — GROUND
                 (SHAPE the land, then paint the soil, then flood it — the strip is sectioned
                 `shape` / `surface` because those are two different jobs), COVER (zone density +
                 clearings), DECOR (flora), PROPS (stone/timber/fire), **INTERACTABLES** (the things
                 the player OPENS — chests, and their contents), UNITS (foe spawns) —
                 and **only the ACTIVE layer is
                 live**: every layer stays visible but a click can only pick, place or erase in
                 the one you are on, so dressing ferns can never nudge a chapel. Each layer
                 ends in its own scoped ERASE brush and remembers the brush you left it on.
                 **WHICH LAYER STOCKS A KIND IS `props.stock`**, read off INFO's own flags (`flora` →
                 Decor, `interact` → Interactables, else Props) — the editor's palette, its group chips
                 and the object viewer's shelves all ask that one question, so a kind cannot be offered
                 on two layers or on none. A chest is still an ordinary `at` op of kind `.chest`, which
                 is why the shipped map did not move when the layer was added; and Interactables has no
                 scatter brush on purpose, since contents live on the OP (`Op.loot`) and a generator
                 would put the same list in every box it grew. **The marked set does not cross layers**
                 (`setLayer` clears it): `marked` holds op indices on the object layers and foe indices
                 on Units, and Del reads it against whatever layer is live now.
                 SELECTION IS BY CLICKING THE THING IN THE WORLD — there is deliberately no list
                 of ops (that was the document model showing through the window, and it read as a
                 history log next to Undo/Redo). A properties
                 panel per op kind, world gizmos, minimap, whole-map undo/redo,
                 New/Open/Save/Save-As (an unsaved map always confirms first), SHIFT+DRAG
                 marquee, drag-the-selection-to-move, Ctrl+C/X/V/A, F5 playtest.
                 **CONTROLS ARE THE OWNER'S, VERBATIM — do not invent additions:** LMB click
                 picks an object, LMB drag PANS; RMB click on an object opens its menu, on
                 nothing DESELECTS, RMB drag ROTATES (4 px splits click from drag); wheel ZOOMS;
                 WASD and the arrows pan; Enter confirms, and **Esc backs out one level, where one
                 level up is SELECT MODE** (owner's rule: Select is "back out and let me grab
                 something", then Esc again is "back out fully"). So the ladder is context menu →
                 Select → DESELECT → the menu. Deselect sits after the brush→Select step and not
                 before it, so backing out of a brush still reaches Select with the selection you were
                 backing out to work on intact; the next Esc is what drops it. Right-click on nothing
                 deselects too. The camera is an ORBIT rig
                 (ground focus + yaw/pitch/dist), not a free-fly, and the pan works by re-aiming
                 at the point the cursor GRABBED — so terrain stays under the pointer at any
                 zoom or angle. THE CURSOR IS SHOWN here and re-hidden on the way out; gameplay
                 hides it because there the mouse IS the camera.
                 SELECT MODE exists because "click to select" and "click to paint" cannot share
                 the left button: it is armed by default, any brush disarms it, Esc re-arms it.
                 **IT LIGHTS WHAT A CLICK WOULD TAKE** (`Editor.hover`, drawn on the object itself),
                 recomputed every frame and never latched — in a wood of eight thousand instances,
                 "which one am I about to get" was a question you could only answer by getting the
                 wrong one first. `hoverInLayer` is the same pick `pickInLayer` makes, asked without
                 changing anything, so the box can never lie about what the click will do.
                 Tab cycles layers, 1-9 pick a brush, [ ] size it, G snaps. **HAND TOOLS LEAD EVERY
                 STRIP** (owner's rule): the brush that puts exactly one thing where you clicked is
                 first and the scatters follow it — Decor opens on `Single`, Props on `Stamp`, Ground
                 on the sculpt tools. A row is only labelled with a digit if that digit reaches it
                 (Ground has twelve brushes and the keys stop at nine).
                 GIZMOS RIDE THE GROUND, not a plane: their `y` is a LIFT above the terrain, sampled
                 per vertex (`liftAt`, `groundLine`). A brush ring drawn at a fixed height is buried
                 in the near side of a hill and hanging over the far side — and the ring is the thing
                 you SCULPT with. The minimap hillshades the same field for the same reason.
                 The CLIPBOARD is file-scope and outlives a map load on purpose, so a stand of
                 trees can be carried from one map into another; its contents are stored
                 relative to the selection's centre, so a paste lands under the cursor.
                 **A CONTROL THAT IS NOT IN THE CRIB IS A CONTROL NOBODY HAS.** The SHIFT+DRAG
                 marquee worked on every op layer from the day it was written, drew its box while you
                 dragged it, and was still reported as a missing feature — because the status line's
                 control crib never mentioned it. It does now, in all four fitted lengths.
                 It draws with the RETRO PASS BYPASSED and in a real SYSTEM MONOSPACE face
                 (Consolas, then the other stock fixed-pitch faces — `hud.mono`, NOT Balthazar,
                 and NOT raylib's bitmap font): you cannot dress a world through a lens that is
                 lying about it, and columns of numbers need fixed advances.
                 Chrome text FITS ITSELF to the space left over — the status readout is laid out
                 first and the control crib shortens, then drops, rather than drawing over it.
- `objview.zig` — THE OBJECT VIEWER (editor top bar > **Objects**, or right-click a selection >
                 **View {prop}…**, or the properties panel's **view**). A paged GALLERY of every
                 placeable kind, SHELVED BY LAYER (Decor = the flora palette, Interactables = the things
                 that open, Props = the rest — off `props.stock`, the same split the brush palette
                 uses), each cell a LIVE off-screen render of the
                 real model through the real scene shader — never an icon, so a mesh that reads wrong
                 here reads wrong in the game. Drag a cell to spin it, wheel to zoom, click to open
                 ONE object filling the screen with its INFO row beside it (bound / top / view /
                 casts / colliders / surface — half of "why does this prop look wrong" is a row in
                 INFO disagreeing with the mesh). Two levels, and Esc backs out one at a time. The
                 preview runs no depth pass, so it calls `gfx.Scene.shadowsOff` — without it every
                 fragment is tested against the WORLD's shadow map and the model comes back dark.
                 It replaces `--shot-props` as the way to judge a model: same look, no rebuild.
                 Its EAR-SIDE twin is the **JUKEBOX** (top bar > **Sounds**): every voice in
                 `audio.zig`'s bank as a list — names walked off `sfx.Id` at comptime, so a new voice is
                 in it the moment it has a row — a click or up/down plays it, space replays, and the
                 selected row's own dials (gain / reach / takes / poly / jitter / submix) sit beside it,
                 because a sound you cannot hear is usually explained by its `reach` or its trim. It can
                 audition AT THE EAR or out at the camera focus, which is the only way to judge the
                 distance falloff and the pan. The editor is muted (`sfx.mute`, off `editor.on`) so the
                 mute makes an exception for it (`editor.auditioning`), and the editor calls
                 `sfx.listen` with its own camera or a world audition would be measured from wherever
                 the GAME camera last stood.
- `ui.zig`     — the editor's immediate-mode widget kit, lifted from `../zig-diablo/src/ui.zig`
                 and re-backed onto `hud.zig`. `Ctx.anyHot` gates world clicks NEXT frame.
- `uiart.zig`  — the chrome's DRESSING (stone plates, gilt frames, jewels, dividers, sheen),
                 shared by hud/menu/ui the way `propart.zig` is shared by the props. Adapted from
                 `../zig-diablo/src/hudx.zig` and `../crawler`'s theme kit.
- `icons.zig`  — the editor's GLYPH SET, drawn from primitives (`ui.Icon` re-exports it). Vector, not
                 an atlas: the buttons scale off `hud.MONO` and a bitmap icon would be the one thing in
                 the chrome that blurs when the type size moves.
- `rumble.zig` — CONTROLLER RUMBLE, and the reason it is its own file: raylib's GLFW backend STUBS OUT
                 `SetGamepadVibration`, so on Windows this resolves `XInputSetState` from whichever
                 xinput DLL is present and drives the two motors itself. Holds the combat beat
                 vocabulary (`hit_light` … `death`) — each beat its own SIGNATURE, blended
                 strongest-wins — and `PAD`, THE pad index both this and game.zig's polling must use.
- `bake.zig`   — the one-way door that emitted the first map from the old code-authored regions.
- `env.zig`    — THE WORLD: the TERRAIN (the sculpted heightfield, its tiled mesh and skirt, and the
                 ground/slope/step queries every actor stands on — see ELEVATION), the REPLAY of a
                 map's ops into props, the
                 `coverField`, and the three systems that make this size affordable —
                 the UNIFORM GRID, the CULLERS (`View`/`Cull`), the grid-local solid queries.
                 Also gathers each fire's `gfx.Light` and uploads the nearest per frame.
                 **AND THE OCCLUDER FADE** (`markOccluders`): a prop of a kind that `fades`, standing
                 between the lens and him, goes THIN — plain per-draw opacity, lit pass only, depth mask
                 off (the same path the aim camera's own fade takes). Never invisible (`OCCL_FLOOR`), and
                 keyed to HOW MUCH OF HIM IT HIDES, measured against the COLLIDERS rather than the bound,
                 because a bound is a canopy's whole spread and every tree within seven metres of the line
                 was thinning off it. Three rules keep it from reading as a switch, which is the whole
                 difficulty — a fade you notice happening is worse than no fade:
                 - **THE GEOMETRY SETS A TARGET, TIME GETS YOU THERE.** `fadeTo` is a pure function of
                   the sight line; `fade` is what draws, walked toward it at a fixed rate (`OCCL_IN` 0.16 s
                   in, `OCCL_OUT` 0.34 s back — OUT IS SLOWER because a trunk hardening over the hero is
                   the uglier half). Cover can cross the whole `OCCL_MIN`..`OCCL_FULL` window in two frames
                   when the camera whips, so a target-only fade IS a switch however smooth its curve.
                 - **IT STOPS BEING IN THE WAY OVER A BAND, NOT AT A PLANE** (`OCCL_DEPTH_BAND`). Cut at
                   the plane through him, a trunk he walks past went fully thinned → fully solid in one
                   frame, and it happened right over him where it shows worst.
                 - **`OCCL_MAX` COUNTS WHAT IS IN FLIGHT**, thinning and recovering both, so it is bigger
                   than any one sight line needs; full, a prop simply stays solid. And `materialize` clears
                   the list, because those are prop INDICES into a world about to be replaced.
                 - The clock is `game.drawDt` — the REAL frame time, not the time-scaled one, and `--shot`
                   parks it at `shots.SETTLE_DT` so a single-frame capture shows the fade's END state.
**HOW THE FILES ARE DIVIDED** (and why, because the rule is not "keep files short"): the thing being
minimised is HOW MANY TOKENS IT TAKES TO MAKE A CORRECT CHANGE. That favours COHESION, not size — a
900-line file whose contents all change together is fine, and splitting it into forty files makes the
work harder, because then finding the code costs more than reading it. So the splits here are on
lines where the concerns genuinely part company, and each new file is named so the first grep lands:
- `props.zig` is the VOCABULARY and the TABLE (kinds, groups, INFO, `info()`); the meshes live in
  seven `prop*.zig` files by family — `propart.zig` (the palette + shared weathering moves),
  `propruins`, `propbuild`, `propvillage`, `proprock`, `propwood`, `propflora`, `propfx`. The
  qualifier in each row (`.build = wood.snagMesh`) IS the pointer to the file. Bark reads pale? That
  is one file, and it is the file holding every other thing made of wood. It also holds
  `deadLimbInto` — see NOTHING DEAD IS STRAIGHT — and the reason the peeling bark on `tree` is SUNK: a
  strip stood off along its whole length (it was up to 0.16 clear of a bole of radius 0.2) is a dark tube
  floating beside the trunk, and that plus the spoke branches was the whole of "the branches are floating".
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
                 that across four places and forgetting one failed SILENTLY. The shared weathering
                 helpers (`courseInto`, `courseStack`, `quoinsInto`, `lichenInto`, `chipsInto`,
                 `crackInto`, `tuftInto`) live one file over in `propart.zig` with the palette, and
                 every ruin ages through them. Big props with many
                 instances come in VARIANTS — the great trees (`bigtree`/`bigtree2`/`bigtree3`) and
                 the six `CLIFFS`. A wood picks among them through its op's WEIGHTED `mix=`, which is
                 why only the rim has a `Kind` set here to seed from.
- `frog.zig`   — THE GAPING TOAD + the `Knot`. Squash-&-stretch rig, hop/lunge/chomp AI, huge
                 reactions, death → a grace-gold mote DISSIPATION (never a hard vanish).
- `archer.zig` — THE SKELETAL ARCHER + the `Line`. A bare-bones humanoid FOUNDED ON THE HERO RIG, and
                 **A FOOT TALLER THAN HIM** (`SCALE` is DERIVED off `hero.H`, not a magic 1.17).
                 KITE-only AI (holds a range band, never melees) plus one panic **BACKSTEP** on a
                 long cooldown — see below. Slowish arrows that STICK and fade; their homing is a
                 LAUNCH NUDGE that fades out over `ARROW_HOME_FADE`, so a sidestep beats a shot.
                 Arrows are a pool owned by `game.zig` and they respect COVER (each flight-steps
                 against the solids in its own travel neighbourhood — `game.arrowCover` →
                 `env.nearSolids` — thunking into stone while still arcing over low kerbs. That
                 flight is sampled by the LENGTH of the step (`coverHit`, `COVER_STEP`) and not at two
                 fixed points: two were honest at a skeleton's 15 m/s and stopped being honest at the
                 hero's 40 m/s aimed shaft, which opens the gaps to 0.33 m at 60 fps and 0.67 m on a
                 slow frame — a fence post fits in that. NOT a
                 whole-list `env.solids()`: that accessor was removed for having no caller, and every
                 real path goes through the prop grid on purpose).
- `ogre.zig`   — THE ONE-EYED OGRE + the `Grief`. A giant (`SCALE` 2.4, ~2.2x the hero to the crown —
                 it went 2.5 → 2.1 as too big and back up on the owner's call), hunched, hefting a knotted
                 CLUB, one dull-amber eye. FOUNDED ON THE HERO RIG but grown to 24 bones (a hinged
                 JAW, TOES, a HUMP, a shoulder GIRDLE); three are inserted ABOVE existing bones, so
                 `poseUpper` sets bones in DEPENDENCY order, not index order. HIGH POISE + two
                 attacks: the OVERHEAD SLAM (long tell → fast crash → long recovery, a crush strip
                 down the facing line) and the FAST SIDE SWIPE (a horizontal scythe through a
                 sector he keeps pivoting into). **HE DOES NOT STRAFE** (`latB` pinned to 0) — he
                 answers a flanking hero by PIVOTING. **THE CLUB NEVER TOUCHES THE GROUND while
                 carried.** Every hurt shape is MEASURED off the posed club (`clubLowWorld()`),
                 never guessed, and unit tests re-assert them — retune anything and RE-MEASURE.
- `kobold.zig` — THE KOBOLD WARBAND + the `Warband`. THREE ROLES OF ONE CREATURE in one file and one
                 struct (berserker / priest / slinger), because the body, gait, fur, death and reactions
                 are shared and only the KIT and the state machine differ. Doglike, on the shared humanoid
                 scaffold. THE PRIEST IS WHY THEY ARE ONE GROUP: it heals whoever is worst off, so
                 something has to see the whole band, and `Warband.update` resolves the heal (the priest
                 owns the animation, never the targeting). Three things ride matrices rather than bones —
                 the off-hand axe, the hinged JAW (`gape`) and the TAIL chain — which is the pattern for
                 anything the 18-bone scaffold has no slot for.
                 **THE SLING THROWS FIRE** (owner's call): a pitch-soaked rag clump, all of whose damage is
                 FIRE (`CLUMP_HIT` — the stone's own 10, retyped, so the threat did not move; `archer.Shot`
                 calls it `.clump` because nothing slings a plain stone any more). The tell is the FX and
                 they are the whole point of it: embers shed off the pouch the entire time the sling goes
                 round (`emitWhirlEmbers`), a puff at the release (`releaseSparks`), and a bigger burst
                 wherever it lands (`impactSparks`, reached through `Warband.splash` the way the venom
                 reaches `brood.splash`, because what landed belongs to the GROUP and not to the arrow pool
                 that flew it). The loaded pouch is drawn ALIGHT — a grey pebble in it promised a rock and
                 threw a fire. **A BITE IS A WAIST AND A SNAP IS A
                 REVERSAL:** the bite folds at the waist and the neck EXTENDS through that fold so the
                 muzzle leads it — pitched nose-DOWN instead (which is how it shipped, 49 deg of it
                 over a pelvis that never moved, with both arms flung up and out) an animal biting you
                 reads as one squatting to relieve itself. **AND A LEAP IS ONE KNEE UP** (owner's law):
                 the dash coils on the ground, throws the lead knee to the chest with the trail leg
                 left extended, and absorbs on landing. Both legs tucked to one shared amount is a hop,
                 and tucking them off `dashU` — which is clamped to 0 through the whole gather — puts
                 the anticipation AFTER the thing it anticipates. **EVERY BONE NEEDS A MATRIX EVERY FRAME:**
                 the death pose skipped the six leg bones and handed `drawMesh` UNDEFINED matrices for a
                 whole release, which is what `66c_kobold_death.png` exists to catch.
- `brood.zig`  — THE BROOD MOTHER, HER SACS AND HER BROODLINGS + the `Brood`. Two ages of ONE spider in
                 one struct and one array, the warband's pattern for the warband's reason: the mother has
                 to see her own clutch to know whether to lay, and the clutch is what turns into the
                 hatchlings. **SHE IS A GUARD, NOT A HUNTER** — slow (0.52 of the hero's walk), tethered to
                 her eggs by `M_GUARD_R`, spitting at anything in the band and biting anything that
                 reaches her. **THE GLOB IS NOT THE WEAPON, THE FLOOR IS** (owner's call): a hit is 5 HP
                 and where it lands becomes a `Pool` of acid that burns in PULSES (`ACID_TICK`) for ~15
                 HP/s, so crossing one is cheap and standing in one kills. **THREE SACS AT A TIME, ONE
                 HATCHLING EACH** (`MAX_SACS` / `PER_SAC`, owner's call), and a sac is a real target — its own HP through the same `foe.strike`
                 everything else uses, and one cut open hatches NOTHING, which is the whole reason to push
                 in past the spit. The hatchlings are fast, leap, and die to a single light. Everything
                 hangs off one rig, parameterized by a `Skin` (colours, abdomen, claw length) so a
                 hatchling is its mother at a different age rather than a second creature to keep in step.
                 **HER POISON IS CHAOS, SPIT AND PUDDLE ALIKE** (owner's call) — one fluid, one element, so
                 `M_SPIT_HIT` carries no physical at all (its poise is the only physical thing about a
                 caustic glob) and the floor's pulses go through `acidPulse`. A hero with no chaos
                 resistance takes exactly what he always took, which is why the retyping moved no balance.
                 **AND THE CLAWS ARE THE SILHOUETTE:** flat blades standing on EDGE, carried up and
                 forward on arms mounted above the leg line — authored flat or slung at leg height they
                 are two more of the eight legs, which is what the first three passes of this looked like.
- `warrior.zig` — THE SKELETAL WARRIORS + the `Muster`. TWO ROLES OF ONE CORPSE — a SHIELDMAN with mace
                 and kite shield, and a GREATSWORD — in one file and one struct, the warband's pattern for
                 the warband's reason: they are `archer.zig`'s skeleton (its `boneMeshes`, its feet) with
                 something else in the fist, so only the kit and the state machine differ — and A HAND
                 TALLER AGAIN THAN HIM (`SCALE` is DERIVED off the archer's own, which is derived off the
                 hero's stature: never a magic 1.26).
                 **A ROLE'S MOVESET IS DATA** (`Attack`, and a slice of them per role), which is what lets
                 the greatsword carry two answers without a second state machine to keep in step.
                 - **THE SHIELDMAN BLOCKS YOU** — `combat.GUARD_ARC` off his facing, the hero's own rule
                   from the other side, paid for out of his own `combat.Stamina.initFoe` pool. A blocked
                   blow is NOT a hit: no hit-confirm, no flinch, and `guardChip` is all that gets through.
                 - **AND HIS BOARDS ARE THIN.** Four hero lights or two heavies empty them, and emptying
                   them UNDER A BLOW is a GUARD BREAK: he goes **down on one knee** and the shield is
                   **smashed off him for good** (owner's call). `shieldGone` is a latch nothing clears —
                   the mesh stops drawing, `guardUp` is false forever, and the rest of that fight is a
                   different fight. It is the biggest reaction in the file and the whole point of him.
                 - **WHAT A WARRIOR HITS YOU WITH IS THE POSED WEAPON** — `tryReach` tests the segment
                   the kit itself swept between last frame and this one (`KIT_SEG` ridden through
                   `xf[WPN]`, the ogre's `clubLowWorld` law carried all the way) against the COLUMN the
                   hero stands in, so a blow that never came near you cannot land and one over your skull
                   or in the dirt at your feet is a miss. `Attack.reachOut` is a MEASUREMENT of that
                   swing, kept for the AI's trigger range alone (the test itself is shared —
                   `foe.weaponReaches`; the kit's LENGTHS and WIDTHS are one set of constants the meshes
                   and the hurt segment both read, or a blade lengthened in the modeller keeps its old
                   reach — that is how the greatsword's point came to sit 0.12 m inside its own steel). It shipped the other way round — an
                   annulus sector guessed off his yaw — and the two drifted until the mace fired at 2.8 m
                   off a head that never left 0.6 m of his own chest, which is exactly what the owner
                   read as "the weapon barely moves but I get hit". Re-tune a swing and RE-MEASURE: the
                   tests drive whole strokes through `swung()` and re-assert reach, tell height and that
                   nothing ploughs the turf.
                 - **A STROKE KEEPS THE WEAPON'S ATTITUDE SMOOTH, NOT ITS WRIST ANGLE** (`swingTilt`).
                   `wpnTilt` is a wrist channel; held steady through a 220-degree shoulder sweep it
                   leaves the weapon radial to the arm at the bottom of the arc, and two metres of steel
                   on a two-and-a-half-metre skeleton then goes 0.44 m UNDER THE TURF beside its own
                   boot. So the swings author where the kit POINTS in the world (0 straight down, 90
                   level, 180 stood on end) and the wrist is handed whatever that costs. Both kits are
                   authored pointing UP out of the grip (they were built in the archer's bow frame), and
                   `wpnFit` is the flip that makes a carry a big number and a blow a small one.
                 - **THE ARM GOES LONG AT THE BLOW.** An elbow still folded at impact keeps the head
                   inside his own silhouette however far the numbers say it reaches.
                 - **THE DIAGONAL SLAM IS UNINTERRUPTIBLE** (owner's call) and `hyper` is a property of
                   the MOVE, not of the creature: damage lands, poise and stance are taken off the blow,
                   and only death stops it. Long tell, long reach, long recovery.
                 - **…AND THE LUNGE IS THE ANSWER TO HIM**: a quick two-stroke combo you CAN interrupt,
                   opening with a little LEAP (`Attack.lunge`/`hop`, travel integrated off a curve like
                   the archer's backstep, and A LEAP IS ONE KNEE UP — see kobold.zig's law). A combo's
                   follow-up runs on `chainWind` and does not re-telegraph, or it is two attacks.
                 - **THE MACE IS NOT FAST** (owner: "swing too fast"). Its windup is a GATHER, a cock and
                   a held shiver — three beats, not a lerp between two poses. An arm that starts
                   travelling on frame one has no anticipation in it and reads as weightless however long
                   the clock says it is.
                 - **AND A TELL IS A SILHOUETTE** (owner: "windup hard to see"). The cocked kit is carried
                   clear of the skull — MEASURED 2.35 m for the mace head and 2.83 m for the point,
                   against a 1.72 m shoulder line — and grit comes up off the load whichever move it is.
                   The mace cock shipped at 1.34 m, which is chest height on its own owner: a windup
                   inside the outline is not a windup.
                 - **THE SHOULDER CHANNELS ARE POSITIVE-IS-FORWARD**, the inverse of the archer's, because
                   `poseUpper` negates on the way in. Authored the obvious way round, the guard arm swings
                   BACK and the boards hang at his hip covering his shin. That is how it shipped first.
                 - Its FX are DUST, BONE and IRON — a skeleton does not bleed. Chips off a landed blow,
                   sparks off the boards, splinters when they go, a crater under the slam, and plumes at
                   both ends of the leap.
- `foe.zig`    — THE FOE STANDARD: the shared contract + behaviours every enemy plugs into, so
                 lock-on, HP bars, collision, the blade hit-test and the combat beats are written
                 ONCE. Holds `Blade` and `strike()` (the HERO's blade into a foe) and
                 `weaponReaches()` (a FOE's swung kit into the hero — the segment it swept across one
                 frame against the COLUMN the hero stands in, `HERO_LOW`/`HERO_HIGH`, so a blow over his
                 skull or into the dirt at his boots misses), `Blow` (a landed hit AND where it came from —
                 the hero's shield covers an arc, so a bare Hit cannot be answered), the telegraph
                 PARTICLE pool (plus the two burst
                 colours that are the WORLD's and not one creature's — `DUST` and the grace-gold
                 `MOTE` every corpse dissipates into), and the Group plumbing: `resetGroup` /
                 `drawGroup` / `anyDied` / `totalHits` / `runesDropped` / `aliveCount`.
- `combat.zig` — …also GUARDING's rules (negation, stability, the arc) and `HitOutcome`, the answer
                 to "what became of that blow" that the whole felt-beat layer switches on. And
                 `Regen` — HP back over TIME, the third healing shape after `tick` (never HP) and
                 `heal` (instant): a drip you set going and then have to SURVIVE. **MUSHROOM JERKY**
                 is the first item to use it, and the first item in the game that does anything at
                 all — more total healing than a Crimson at a fifth of the rate, so it is worth
                 eating BEFORE a fight and nearly worthless inside one. Used from the INVENTORY
                 (`item.Use` names the effect, `game.useItem` performs it, `item.usable` is the one
                 test that decides whether a row may be pressed — so the list cannot offer a Use
                 that turns out to be a no-op, which is why it offered nothing until now). Two sit
                 in the chest by the kobolds, and a test pins that they are still in the map.
- `combat.zig` — SHARED `Vitals`: HP + the two-tier stagger + regen + death + `heal`/`needsHeal` (the
                 one path that moves a foe's HP UP — `tick` never does, "flasks only" — and it CANNOT
                 raise the dead, because `dead` is a latch the whole foe standard reads). Plus `Stamina`,
                 the HERO'S ALONE (a foe meter nothing reads would only rot). Pure logic,
                 unit-tested. THE place to retune damage/poise/stamina feel.
- `combat.zig` — …and DAMAGE TYPES: `Elem` (PoE2's fire / cold / lightning / chaos), the `Elems` bundle a
                 `Hit` carries beside its physical `dmg`, and the `Resists` every `Vitals` mitigates it
                 with. See RESISTANCES — physical is deliberately not one of the four, 75 is the cap,
                 negative amplifies, and each foe's table is authored in its own file.
- `item.zig`   — THE ITEM VOCABULARY: `Kind`, its display name, its map `tag`, and `Use` — what
                 using one DOES, named here and performed in `game.useItem`. Plus the `Bag`, a
                 saturating count per kind (`nth` walks only the rows that hold something, so a
                 menu cursor can never land in a hole). MUSHROOM JERKY is the only kind with a
                 `Use` today; `usable` is the one test the inventory presses a row on.
- `stats.zig`  — THE CHARACTER SHEET: seven attributes (Vitality / Mind / Endurance / Strength /
                 Dexterity / Intelligence / Luck), a name and a says-what-it-does line each, and the
                 CURVES that turn three of them into the bars — `hpFor` (Vitality), `fpFor` (Mind),
                 `staminaFor` (Endurance), each `base` at one point then a rate per point that falls off
                 at ER's own documented SOFT CAPS (`docs/ELDEN_RING.md` §2/§3; the stamina curve IS ER's
                 table, 1 → 80 … 99 → 170). Three things are load-bearing:
                 - **THE STARTING SHEET REPRODUCES THE TUNED BARS EXACTLY.** Every attribute starts at
                   **15**, and 15 is where each curve yields the 70 HP / 60 FP / 105 stamina the game was
                   already balanced around — so `hero.HP_MAX`, `combat.FP_MAX` and `combat.STAM_MAX` are
                   now *derived* (`stats.hpFor(stats.START)` and friends) and nothing moved. A test pins
                   all three, because a curve retune that quietly shifts the hero's HP silently invalidates
                   every foe's damage, which is measured against `HP_MAX`.
                 - **THE BARS TAKE THEIR SIZE FROM THE SHEET IN ONE PLACE** — `hero.makeWhole`, the grace /
                   respawn / bonfire restoration. It is the only moment a sheet could have changed and the
                   only moment a bar may resize; the alternative is three maxima updated at four sites,
                   one of which is always forgotten.
                 - **THE FOUR NOTHING READS YET SAY SO** on their own row. An inert attribute the player
                   cannot tell is inert is the same lie as inventing a sorcery for the HUD's empty slot.
                   There is no leveling and no criticals, so nothing spends points and Luck is drops only.
- `chest.zig`  — THE OPENABLE BOXES: a `Site` per `.chest` prop the world placed, a `near` pick
                 inside `REACH`, an eased lid `swing`, and `openNear` — which reads the contents
                 off the PLACING OP (`Op.loot`), so a chest's stock is authored in the map and
                 not in the code. Opening is once-only and an out-of-range op index yields an
                 empty list rather than reading past the map.
- `rest.zig`   — SITTING AT THE BONFIRE, and now at a **CAMPFIRE** too. `isRestKind` is the ONE predicate
                 that decides what you can sit at, and the lit campfire is a FULL grace (owner's call) —
                 the same restore and the same world reload, because the one thing worse than a second
                 rest kind is a second rest kind with its own half-rules. **THERE ARE TWO CAMPFIRE KINDS
                 AND THE DIFFERENCE IS THE FIRE**: `campfire` is the **Extinguished Campfire**, cold ash
                 in a ring of stones, dressing only and carrying no `light`; `campfire_lit` is **Campfire**,
                 which burns, is shelved under the editor's **Interactables** layer beside the chests
                 (`INFO.interact`), and is a place to sit. Both are built from ONE `hearthInto` off ONE
                 seed, so they are the same fire at two different hours rather than two props. The shipped
                 map's three campfires are the EXTINGUISHED kind now, which is why its fire count went
                 40 → 37; swapping one to `campfire_lit` in the editor puts the fire back and gains a
                 grace with it. Also the four-phase state machine (`off`/`in`/`sit`/`out`),
                 the fades either side of it, the dusk `dim` and the fire bed's level, and the
                 `seat` the hero takes (a spot off the fire, three-quarters on to the lens). The
                 EDGES (`justEntered`/`justLeft`) are one-frame flags `game.tickRest` hangs the
                 world reload off.
- `collision.zig` — 2D XZ capsule/circle footprint collision (push-out).
- `mathx.zig`  — ground-plane + vector/angle helpers.
- `audio.zig`  — THE SOUND BANK: ~80 voices, every one SYNTHESIZED at launch from the same handful of
                 layers (`body` / `air` / `grit` / `ring` / `tick` / `growl` / `chirp` / `choir` /
                 `sparkle`, plus `hall`) through one
                 shared tape-style `master`, which is what makes separately-authored sounds feel
                 recorded in the same room. Read it as recipes.
                 **THE HEAL IS CHORAL** (owner: choral and heavenly, reverby and sparkly, still lo-fi) —
                 `mkKoboldHeal` is an open chord SUNG rather than played: root / fifth / octave / tenth
                 entering in that order so it RESOLVES upward, a low octave under it, a `sparkle` of
                 pentatonic bells over the top, and a `hall` long enough to be a room the kobolds are not
                 standing in. It used to be one high `ring`, which read as a UI ping mid-fight. Three
                 things the new ops get right and can be checked by a test on the render:
                 - **A CHOIR IS FORMANTS PLUS DISAGREEMENT.** Two resonant peaks (~730/~1090 Hz) make the
                   vowel; per-voice detune, vibrato rate and entry make it VOICES. One of each is an organ.
                 - **`hall`'s GAIN *IS* ITS DECAY TIME.** Trimming a comb's coefficient by a separate
                   "wet" factor shortens the tail instead of quieting it — the first pass did exactly that
                   and bought a 0.3 s room out of a 1.35 s ask. Level is `norm`'s job, at the end.
                 - **A SPARKLE IS ON A LADDER.** Scattered high bells are picked off a pentatonic set, so a
                   shimmer never lands on a note fighting the chord under it; random pitches read as a
                   broken wind chime. The FLASK gets four of them, quiet, on the bloom (owner: the drink
                   itself is fine, just a slight sparkle).
                 Three more things to know before retuning:
                 **`master` NORMALIZES each voice** (`norm`), so a layer's `amp` sets its BALANCE
                 inside the voice and only `BANK.gain` sets how loud the thing is; **THE FIGHT IS ONE
                 BAND** — every combat row above `BATTLE_FLOOR` (0.34) is `sqrt(BATTLE_FLOOR × old)`,
                 a geometric pull toward the soft end that HALVES the spread in dB (owner: "some battle
                 sfx is much louder than others… normalize to the softer ones"). It was 0.26–1.00,
                 nearly 12 dB, so an ogre's slam arrived four times the size of the swing answering it.
                 Two properties make it a compression and not a volume knob: the soft voices do NOT
                 move (a normalize that raised them would be one), and every ORDERING survives, so the
                 slam is still the biggest thing in the game. **Retune by moving the FLOOR**, not by
                 pushing one row back up; a test pins the band's ratio and the orderings that carry
                 meaning. Excluded rows sit at or under the floor already and would have been RAISED:
                 the boots, the roll, both swings, `refused`, `arrow_dirt`, the priest's cast and heal.
                 **THREE FAMILIES** (`Submix`: `sfx` / `combat` / `ambience`) — a row's `mix` is both
                 where it sits in the AUTHORED mix (`submixTrim`: only ambience is trimmed, 0.55) and
                 which OPTIONS SLIDER the player moves it with. Combat exists as a family for the
                 slider's sake and keeps trim 1.0, which is what leaves the reverted `.creature` trim
                 reverted. Row gain × family trim × player dial meet in `levelFor` and nowhere else;
                 `setVolume` also re-levels the BEDS mid-flight, since those re-trigger only every
                 eight seconds and would otherwise ignore the slider until then.
                 **`gain` and `reach` are separate dials** — the ogre's LEVEL is compressed with
                 everybody's, his 135 m reach is not; **`vars`/`jit`/
                 `vjit`** are the anti-grate dials (different takes, then pitch, then level); and a
                 voice's shape is judged by EAR — the tests only prove it renders, stays in range and
                 is not silence. An arrow's impact is chosen by the SURFACE it struck
                 (`arrowImpact`): masonry and iron ring, flesh, earth and timber must not.
                 **SPACE IS THE OTHER HALF OF IT**, and it is built from three things, because raylib
                 hands us only volume / pitch / pan per playing sound. (1) **EVERY VOICE CARRIES ITS
                 OWN `reach`** — a croak dies at 30 m, an ogre's slam carries 135, a birdcall 210. One
                 shared range got both ends wrong: toads murmured through terrain you couldn't see them
                 in while the slam went silent short of the plaza. (2) **DISTANCE IS SPECTRAL, NOT
                 JUST LEVEL.** Air eats high frequencies ~15x faster than low ones over the same
                 distance, so a far sound is DULL — turning one down only makes a near sound quiet. The
                 voices that are always far (the wind, the birds) have it BAKED IN (`AIR_FAR_BED` /
                 `AIR_FAR_CALL`); everything else gets a small pitch droop with distance as a proxy,
                 since we cannot filter a voice that is already playing. (3) **THE BED IS TWO
                 DECORRELATED TAKES, HARD LEFT AND HARD RIGHT** (`bed`). Two ears fed the SAME buffer
                 hear one source between the speakers however quiet it is; two independent renders of
                 one recipe have no single place to be, which is the only way a stereo pair puts you
                 inside weather. Its gust clocks are rolled per take for the same reason. FRONT vs BACK
                 is deliberately barely there (`REAR_DUCK`): resolving it needs an HRTF, and in a game
                 where the thing behind you kills you, a rear cue that worked would be a bug.
                 **THE CANOPY IS FIVE VOICES, NOT ONE.** Two are looping BEDS played as a hard-panned
                 pair (`bed`) — the wind, and the CRICKET chirr, built as N independent individuals
                 (own pitch, chirp rate and place in the cycle) because one clock turns a field of
                 crickets into a rhythm section. Their lengths are deliberately unequal, or the loops
                 re-align and you hear it. The other three are sparse CALLS on their own long clocks:
                 two contrasting BIRDS (one stepped, one SLURRED — a glide is what separates a whistle
                 from a blip) and an OWL, the rarest and furthest. Table-driven (`CALLS`: gap band +
                 distance band) and rolled a BEARING AND A DISTANCE through `world()`, never played at
                 the ear. (A WOLF howl was the sixth and is GONE, owner's call, after turning out to be
                 the "skeeter" — nothing was retuned to inherit its range.) The crickets are the ONE
                 ambient voice rendered BRIGHT (`AIR_NEAR_GRASS`): they are in the grass at your feet
                 and the spectral tilt is the only thing that says so.
                 **THE AMBIENCE HAS ITS OWN TRIM** (`Submix.ambience` / `TRIM_AMBIENCE`), applied where
                 a row's gain becomes a raylib volume, so "put the background further back" is ONE
                 number and not six literals with one silently missed. NOTHING ELSE IS TRIMMED — a
                 `.creature` family over the toads and the ogre was tried and REVERTED (owner: "I meant
                 ambient sounds not combat sounds"), and a test pins exactly the beds and the calls so
                 the idea cannot come back by accident.
- `hud.zig`    — UI text in Balthazar; the ONLY path to draw/measure text. Two atlases of the
                 same face: 96 px for HUD, 160 px for the YOU DIED card. Also THE ELDEN RING
                 HUD itself — the three vitals bars and the four-slot equipment cross — taking plain
                 fractions, so it knows nothing about the hero. Colours here are LITERAL screen
                 values (drawn after the retro blit, outside the scene shader), so the
                 author-dark rules do not apply.
                 **THE EQUIPMENT ICONS ARE DRAWN AS OBJECTS, NOT GLYPHS** (owner: cooler, classier, more
                 fidelity, more wabi). A blade has a taper, a fuller, a lit edge and a shadowed one; a
                 shield has planks with grain, an iron binding, rivets and a domed boss; a flask has
                 shaded glass, a liquid line, a wax seal and a cord tie; a bow's upper limb is the longer
                 one, with horn nocks and a served string. Three things are load-bearing:
                 - **WABI-SABI, BUT DETERMINISTIC.** Unequal guard arms, planks of different widths, a
                   nicked edge, a stopper off plumb, a lost rivet — every offset comes out of a
                   FIXED-SEED `mathx.Rng` re-seeded on each call, so the icon is imperfect and *the same
                   imperfection every frame*. A live stream would make the HUD crawl.
                 - **THERE IS NO CLIPPING**, and that is what decides how anything round is shaded. The
                   flask's body is the DARK tone at full size with the lit fill inset up-left inside it,
                   so what shows of the dark is a crescent along the far rim. The three obvious ways all
                   failed: a concentric dark circle is a bubble, a sector leaves a straight chord across
                   the glass, and a big offset circle spills its far side over the world.
                 - **OVERLAP SHAPES THAT SHARE AN EDGE.** The sword's point is its own triangle and it
                   runs well into the body: butted exactly edge-to-edge it came back with a 3 px hole
                   across the blade — found by SAMPLING the render, not by eye.

## The hero rig (`hero.zig`)

- **Anatomy is real.** Bone lengths are fixed fractions of stature `H` (=1.8) from Drillis &
  Contini (1966) as tabulated in Winter. This is why proportions read as human.
- **Forward kinematics.** 18 bones (`hero.N` — the 17 joints plus the SWORD, which is a real bone on
  the right wrist; the humanoid rule below says "the hero's 18" and this line said 17);
  `pose()` chains a world matrix per bone ONCE per frame,
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
- **AND THE 18-BONE SCAFFOLD ITSELF IS SHARED** — `hero.N` / `hero.PARENT` / `hero.restHumanoid(hx,
  sx, stature)`, with bone 17 as the WEAPON slot (`hero.HELD`) on the right wrist whatever hangs off
  it: the hero's sword, the archer's bow, a kobold's axe. Do not transcribe the joint layout into a
  new creature file. It WAS transcribed per creature, under a note in archer.zig saying to lift it
  "if a third humanoid ever appears"; the ogre made three and nothing moved. Only `hx`/`sx` and the
  stature are honestly per-creature. The OGRE stays off it on purpose — 24 bones with three inserted
  ABOVE existing joints is a different layout, not a wider one.
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
- **A CORPSE IS NOT A COLLIDER** (owner's call, and the genre's rule): from the frame a foe dies you walk
  straight through it. `alive()` is only false once `gone`, so it stays true through the whole collapse
  AND the dissipation — seconds of a dead thing you were shouldering past. Every collision site asks
  `foe.corporeal` (`alive() and !dying()`) instead, which is also what `pierceGroup` always asked.
- **Humanoids reuse the hero's walk/strafe** (see the rig rules). Never author a second walk.
- **Group + register.** Wrap instances in a `Group` (`Knot`/`Line`/`Grief`) exposing `anyDied` /
  `totalHits` / `aliveCount`; game.zig iterates groups generically. Its `reset` and `draw` are
  ONE-LINE DELEGATES to `foe.resetGroup` / `foe.drawGroup` — don't re-write either body. The draw's
  `setFlash(0)` tail is the line a fourth copy would forget, and a Group that leaves the uniform hot
  reddens whatever draws next.
- **A GROUP HOLDING SEVERAL KINDS ANSWERS FOR ITS OWN MEMBERS.** The warband and the brood each keep
  two or three foe kinds in one array (something has to see the whole set — the priest's heal, the
  mother's clutch), so their row in `FOE_GROUPS` carries `kind = null` and each member exposes
  `kind()`. `game.memberKind` asks for that method and nothing else: it used to ask whether the
  struct had a `role` FIELD and then hand it to `kobold.kindOf`, which silently labelled the brood's
  roles as kobolds the moment a second creature grew a `role`.
- **A group with anything on the field BESIDES its members exposes `clear()`** (the brood's sacs and
  acid). The shot harness empties the field by zeroing `n`, which leaves everything else standing.
- **Anything the map must be able to post is a `wf.FoeKind`,** appended (never inserted — the editor's
  unit brushes are pinned to that enum's ORDER at comptime), plus a `foeName`, a `unitTips` line, a
  `unitIcons` entry with an `icons.zig` glyph, and a `foeSwatch` colour. Several kinds of one creature
  go in as a CONTIGUOUS RUN so `roleOf`/`kindOf` stay an ordinal shift, and the run is pinned at
  comptime where it is declared.

## ELEVATION — the ground has a shape (`env.zig`, `worldfmt.zig`)

The world is a HEIGHTFIELD you sculpt in the editor (see the Ground-layer bullet above for the storage
and the mesh). This section is the part that decides how it PLAYS.

- **TWO RULES DECIDE EVERY STEP** (`env.walkStep`), and either one passing is enough:
  - the rise ahead is under **`STEP_UP`** (0.55 m) — a kerb, a terrace lip, a step. Always taken,
    however steep the face carrying it. Sized to the ENCODING: heights quantise to 0.25 m, so this
    makes "up to two risers" walkable with headroom and three a wall.
  - or the rise is within what **`MAX_SLOPE`** (tan 40 deg) gives over that distance — an incline.
- **MEASURED OVER A FIXED LOOKAHEAD (`STEP_PROBE`), NEVER OVER THE FRAME'S OWN TRAVEL.** This is the
  one thing here that cannot be got wrong quietly. Against the frame's distance, `STEP_UP` is true of
  every millimetre a 240 fps hero takes into a vertical cliff — so he ratchets up it at tens of metres
  a second, faster the better the machine. A test pins the rule across four frame rates.
- **A REFUSED STEP IS NOT A STOP.** The UPHILL COMPONENT is removed and the rest of the move is taken,
  at full length: walking into a cliff at an angle slides you along it, straight on holds you still,
  and no input is ever dropped. A hard block would put invisible corners all over a hillside.
- **THE STEP RULE IS ALSO WHAT KEEPS THE FOOT OF A CLIFF WALKABLE.** The slope test samples the
  gradient where you are going, and at the base of a cliff that gradient is the cliff's — so without
  `STEP_UP` you would be held a metre off every rock face by a wall you cannot see.
- **FOES GET THE SAME RULES**, applied as a POST-STEP GATE (`game.gateTerrain`): each moved itself
  knowing nothing about the world, and its displacement is re-taken through `walkStep`. AIRBORNE foes
  are exempt — a toad's lunge and an archer's backstep are committed leaps and may cross any GROUND.
  **BUT NOT THE MASONRY** (`game.settleGroup`): airborne exempts a leap from the terrain rule and from
  being shouldered by other bodies, never from `env.resolveActor`, or a pounce crosses a wall and the
  foe has left the arena through it. That push-out is NOT rate-limited the way the grounded one is —
  the correction is one frame of travel, and a leap into stone has to stop at the stone.
- **`pos.y` IS THE GROUND UNDER AN ACTOR**, written in ONE place (`game.groundActor`) for the hero and
  every foe; the rigs only read it. It is **EASED, NOT SNAPPED** (`GROUND_RISE_RATE` /
  `GROUND_FALL_RATE`), and that is the anti-jank measure: a step is a discontinuity the moment you
  cross it, and the camera rides the hero's shoulder, so snapping kicks the whole frame. Past
  `GROUND_SNAP` it plants instead — a respawn must not slide up out of the earth.
- **EVERY WORLD POINT ON AN ACTOR IS MEASURED FROM `pos.y`** — `hero.shoulderPoint`, every foe's
  `centerWorld`/`lockPoint`/`topWorld`, the ogre's crush point, the toad's dust. Measured from the
  datum instead, a foe on a bank keeps its HP bar and its hurt sphere down in the field, and the
  camera frames a point 8 m below the hero (it did — he sat off the top of the screen).
- **THE CAMERA SHORTENS ITS BOOM RATHER THAN BURYING THE EYE** (`camera.followClear`). On a slope the
  boom swings into the hillside constantly; lifting the eye instead would tip the view toward looking
  straight down as you climb, taking the pitch away from the player. It pulls in, and only lifts as a
  last resort. **A low pitch on a steep slope still looks INTO the rising ground** — that is geometry,
  and the answer is the player's own right stick (the shot harness raises the pitch for the same
  reason).
- **THE HERO LEANS INTO THE HILL** (`hero.slopeLean`, `SLOPE_LEAN` 0.55 of the slope, capped at 16 deg,
  eased at `SLOPE_LEAN_RATE`), through the SAME `rx(bodyPitch)` term as the run lean, because it is the
  same motion about the same hinge — the trunk folding over planted feet. A body pitched the FULL angle
  is normal to the ground and reads as welded to it.
- **THE TERRAIN RECEIVES SHADOWS BUT STILL DOES NOT CAST.** A hill shades by its own normal and throws
  nothing across the ground behind it. Self-shadowing a heightfield off a 108 m ortho box puts acne
  everywhere the surface grazes the sun, which is a worse artefact than a missing hill shadow. The
  shadow box now tracks the focus in Y as well (`gfx.beginShadowPass`), or a hero 20 m up carries his
  own shadow toward the box's edge.
- **NO FOOT IK, so feet clip a few cm on steep ground** — the gap AGENTS.md already names, now visible
  in a second place. Props are planted at their ORIGIN only, so a wide base on a slope buries one edge:
  the alternative is tilting props to the ground normal, and a leaning chapel is a louder error than a
  plinth with one corner in the dirt.

## Combat feel

- **The two sides are tuned SEPARATELY** (`combat.zig`). A stagger you inflict is a punish WINDOW
  you must be able to walk into and use; a stagger you suffer is time taken off the player, which
  the FEEL RULES spend as little of as possible. Hence `FOE_LIGHT_STUN_DUR` / `FOE_HEAVY_STUN_DUR`
  well past the hero's, and `FOE_REGEN_DELAY` / `FOE_REGEN_RATE` far slower — a foe whose poise is
  back before your next swing can only be staggered by a burst, and every fight collapses into
  "land two fast or don't bother".
- **NOBODY IS POISE-DAMAGED WHILE ALREADY REELING, EITHER SIDE** (owner's law). For as long as a stun
  runs, incoming **poise is dropped**, and when it ends **poise goes back to FULL** — both tiers.
  Without it the blow that staggered you also set up the next stagger, so a warband or a mashed R1
  held either side in one unbroken flinch, which is the time-theft the FEEL RULES exist to forbid.
  Three parts of it are load-bearing:
  - **HP AND DIRECT STANCE DAMAGE STILL LAND.** The window you opened is still a punish window —
    land a heavy inside a light stun and its stance damage counts. What you cannot do is RE-FLINCH
    something that is already flinching.
  - **THE REFILL AT THE END IS WHAT MAKES IT SYMMETRIC.** A light break already reset poise; a HEAVY
    break resets STANCE and leaves poise where the blow left it, so without this the bigger reaction
    left you the more fragile of the two.
  - **`combat.Vitals` OWNS THE CLOCK** (`stunLeft`, armed by `beginStun`, seeded from the same
    `*_STUN_DUR` pair the rigs pose against and carried per-side by `init`/`initFoe`). `foe.strike`
    applies a blow knowing nothing about the creature it belongs to, so the rule cannot live in the
    rigs. It ticks BEFORE the regen gate in `Vitals.tick` — behind it, a foe's `regenDelay` (2.2 s)
    outlasts both its stun windows and the immunity would never lift. The rigs keep their own `t`
    for the ANIMATION; a test pins the two clocks to one pair of constants.
  - The one door `hit()` does not cover is a **GUARD BREAK** — a heavy stagger the vitals never
    returned, since the chip that emptied the bar was a plain damage hit. `hero.enterStun` arms it.

## STAMINA (`combat.zig`) — the soulslike rules, all of them

- **AN EMPTY BAR LOCKS OUT roll / attack / sprint** (`STAM_LOCKOUT`, owner's call). This does NOT
  break the no-time-theft law: that law forbids taking control away during the player's own
  action, and a lockout is the consequence of a choice made a second earlier, readable off a bar.
- **WALKING IS NEVER GATED.** Running dry drops you to a walk (`mv.speed` is capped to
  `RUN_SPEED`), never roots you. Denied at the SOURCE so `sprintingMove` stays the one definition
  of a sprint and the speed, the facing exceptions and the bleed cannot disagree.
- **RUN IT ALL THE WAY OUT AND YOU ARE WINDED** (`STAM_WIND_CLEAR`, 0.5, owner's call): the sprint
  stays denied until the bar is back to HALF. A LATCH, not a `cur == 0` test — the denial has to
  outlive the emptiness, or the first milligram of regen buys one frame of running that empties it
  again and a spent player mashing Shift walks anyway while the bar strobes at zero. **SPRINT ONLY:**
  roll and attack keep `canAct`'s panic rule. It is latched by `settleWind`, called from every path
  that moves `cur`, so the drain from a sprint and the drain from a roll cannot disagree about whether
  you are spent — and the stamina bar draws the mark it owes (`Stamina.windedTo` → `hud.vitals`),
  because "can I run yet" is a question with an answer whether or not a key is down.
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

## GUARDING (`combat.zig`, `hero.zig`) — the plain Dark Souls block

Hold L1 / RMB and a blow from the FRONT is caught on a small round shield. No parry, no guard
counter (`docs/ELDEN_RING.md` §3 describes both; neither is built) — block, pay, and either punish
the gap or lose your footing. Deliberately the DS1 shape rather than ER's.

- **IT IS A HELD STATE, NOT A COMMITTED ACTION.** `hero.setGuard(want)` is called EVERY frame with
  the button's level and re-derives `guarding` from scratch (`canGuard`). So an attack, a roll, a
  draught, a sprint, a stagger, a death or an empty bar all drop the shield with no bookkeeping
  anywhere — the alternative is a flag six transitions have to remember to clear, which is exactly
  how the draught once resumed out of a roll. **Call it AFTER `sprinting` is settled** for the frame.
- **THE SHIELD IS A DIRECTION** (`combat.GUARD_ARC`, 65 deg either side of his facing), not a bubble.
  Getting round it is the counterplay, and it is why guarding cannot answer a warband the way rolling
  can. A blow with NO direction (a zero `fromDir`) is never blocked — which is what lets the `--shot`
  harness force the flinch/stagger/death reactions with synthetic hits.
- **SO A BLOW HAS TO CARRY WHERE IT CAME FROM.** Every Group's update returns `?foe.Blow` (the hit
  PLUS the attacker's `pos`), not a bare `?combat.Hit`. It used to throw the attacker away at the one
  place that still knew it, leaving the caller to guess from the nearest live foe — and "usually the
  right one" is not a mechanic. An ARROW's direction comes off its own velocity reversed: by the
  frame it connects the shaft is standing in the hero, so its position says nothing.
- **IT COSTS STAMINA, NOT POISE.** A blocked blow deals no poise and no stance — the impulse went
  into the boards, and a block that still flinched you would be strictly worse than standing there.
  The cost is `GUARD_STAM_FLAT + GUARD_STAM_PER_DMG × dmg` (stability), and the refill is PAUSED the
  whole time the shield is up, which is what stops a held guard being free.
- **THE SHIELD IS SMALL AND EVERY NUMBER SAYS SO.** It does not reach 100% negation, so CHIP gets
  through (`GUARD_NEGATE` 0.85) and chip CAN KILL — which is why it goes through `Vitals.hit` rather
  than straight at `hp`, so death latches the same way. And its stability is poor: a kobold's teeth
  cost ~15 of 105, the ogre's club ~45, so the same full bar is a long exchange with the little ones
  and THREE swings of the club.
- **EMPTY THE BAR UNDER A BLOW AND THE GUARD BREAKS** — a heavy stagger, and because the break left
  the pool at zero the shield cannot come back up until it refills. The danger is never that hit; it
  is the next one, landing on a man with no shield and no stamina.
- **`takeHit` RETURNS WHAT BECAME OF THE BLOW** (`combat.HitOutcome`: ignored / taken / blocked /
  guardBroken) and `game.heroTakes` is the ONE place that turns that into a felt beat. Before this,
  every caller fired the hurt beat the moment a foe REPORTED a blow — so rolling cleanly through a
  slam still grunted, shook the camera and kicked the pad, which is the one thing a dodge must never
  do.
- **HE CAN WALK A FIGHT DOWN BEHIND IT** — `hero.GUARD_SPEED` is 0.75 of the WALK (owner's call,
  raised from 0.55). At just over half you could not reposition behind the shield at all: closing or
  backing off meant dropping it, so the block only ever answered a blow you had already decided to
  stand still for. It is the FLOOR that matters, not the ceiling — clearly under 1.0, or the shield
  is free — and it stays capped against the WALK, never zeroed (guarding slows you, it does not root
  you). Denied at the SOURCE in game.zig, like the sprint, so the one `Move` every reader sees
  already knows about it.
- **THE STANCE LAGS, THE BLOCK NEVER DOES.** `guarding` is live the frame the button goes down;
  `guardB` is a VISUAL blend easing in over ~0.1 s (the FEEL RULES' ceiling on a posture change).
  Nothing mechanical may read `guardB`.
- **THE MAN MOVES, THE SHIELD HOLDS.** A caught blow's recoil goes into the BODY — a deep sink, a
  real step back (visual, like the stagger's), the camera and the pad — and only a little into the
  arm. Spending it on the arm instead carried the boards off the centreline and down to his hip, and
  a blow he CAUGHT looked exactly like one that had knocked his guard aside. REACTIONS ARE HUGE still
  holds; the size just belongs somewhere that does not contradict what happened.
- **The shield is not a bone** — it rides the left wrist's matrix through `hero.shieldFit`, the
  pattern `kobold.zig` set for anything the 18-bone scaffold has no slot for. And that fit is
  DERIVED from the stance angles (it is their inverse), or the first retune swings the shield off
  its own arm.

## THE ONE RECORDED SOUND (`audio.zig`)

Everything in the bank is synthesized except the campfire bed, and it arrived sounding like it: clean,
thin and from a different room. It goes through the SAME finish the synth voices do (`dressedFire`) —
saturation, the bit crush, the tape's bandwidth and its noise floor — plus a LOW SHELF, because a fire you
are sitting at is felt in the chest and the take had no bottom in it. raylib streams from ENCODED bytes,
so a processed loop has to be written back out as a canonical WAV; the source file's own length bounds the
buffer, which keeps it right if the asset is ever swapped. No `wow` on it: flutter is a pitch wobble and a
crackle bed has no pitch to wobble.

## LEASHING (`foe.zig`) — a foe's tether, and the provocation that cuts it

A foe drawn a long way from where the map posted it walks back and loses interest until something rouses it
again. One struct (`foe.Leash`) every creature embeds, because all four want the identical rule and four
copies of a hysteresis is four chances to get one of them subtly wrong.

- **START FAR, STOP NEAR.** It turns for home past `LEASH_R` (30 m) and stops only inside `LEASH_HOME_R`
  (3 m). That gap IS the debounce: a foe hovering at the boundary cannot flap between chasing and returning
  every other frame, which a single radius guarantees it would.
- **AND ONLY AFTER `LEASH_CALM` (4.5 s) WITH NO BLOW GIVEN OR TAKEN.** A fight in progress is never
  abandoned — every path that lands a hit or takes one calls `noteCombat`.
- **ONE PLAYER PROJECTILE ROUSES IT FROM ANY RANGE, FOR `PROVOKE_ROUSE` (14 s).** A blade marked `pierce` (an
  arrow today, a spell when there is one — nothing asks what threw it) calls `Leash.provoke`: the creature
  snaps its facing back down the shaft and then HUNTS HIM DOWN, whatever its own `AGGRO_R` says. Shoot
  something across the plaza and it comes. The rouse is a COUNTDOWN, not a level of `provoked`, because it
  has to outlast the WALK — as a threshold it lapsed 0.29 s after the hit, so a sniped foe took one step and
  went back to grazing and sniping read as doing nothing. The tether is still what ends the chase.
- **KEEP AT IT AND THE LEASH BREAKS** (`PROVOKE_BREAK`, held `PROVOKE_HOLD` = 14 s). THE ANTI-CHEESE: standing
  at the end of a foe's tether, poking it, and watching it turn round and walk away is free damage at no
  risk. A single hit deliberately does NOT cancel a return in progress — that is the other half of the
  debounce, and it is what stops one arrow a second flipping a foe's mind forever — but continued aggression
  makes it stop trying to leave at all and prioritise fighting you.
- **IT REACHES FOUR STATE MACHINES BY BENDING THE SENSED RANGE** (`foe.sensedDist`), not by bolting a second
  decision tree onto each. Every creature already knows what to do when the hero is FAR (drift back to where
  it was posted) and what to do when he is NEAR (fight), so walking home reads him as infinitely far and
  being roused reads him as within reach. Only the DECISION sees the bent number — movement still uses his
  real position, so a roused foe fifty metres off walks the right way. The archer is the one that needed a
  homeward walk ADDING (its out-of-range answer was to stand still and scan); the toad, ogre and kobold
  already had one, and the leash just drives it. The ogre's own `homing` is the MOVEMENT half of that — which
  state walks where — where `leash.returning` is the decision.

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
  ER). Actions are
  committed (no mid-swing cancels) with an **ER-style input queue**: pressed mid-action, an
  attack/roll buffers in ONE slot (last press wins; a same-frame roll press outranks attack) and
  fires at the earliest exit — the attack's chain knot or the roll's end. A queued roll leaves in
  the direction HELD at fire time, not pressed.
- **R1 AND R2 ARE THE ARM'S, NOT THE SWORD'S.** The two attack buttons (**R1/RB or LMB**, **R2/RT or
  Shift+LMB**) are read as BUTTONS and routed by which armament is in the right hand — light slash /
  heavy overhead with the sword, quick shot / aimed loose with the bow. Neither weapon can end up with
  a press the other swallowed.
- **Swap right-hand armament:** **D-pad RIGHT** / **Q** — sword ↔ bow. That is ER's own binding for the
  right-hand slot, and taking it back is why **the pad has no camera zoom any more** (owner's call; ER
  has none either, its D-pad being four armament and item cycles). The wheel still zooms on kb+m.
- **Cycle the arrow:** **D-pad UP** / **Y** — plain ↔ fire (see THE BOW). Up is the cross's one empty
  slot, and it mirrors D-pad DOWN / **T** cycling the quick item. Not gated on the bow being out:
  choosing your ammunition is not an action.
- **Guard:** hold **L1/LB** or the **RIGHT MOUSE BUTTON** (ER's own keyboard default for the left
  hand). HELD, never toggled, and never buffered — see GUARDING.
- **Aim:** hold **L2** or — with the bow out — the **RIGHT MOUSE BUTTON**, which is free to take it
  because the bow has already taken the shield away. One button, and which hand it belongs to is
  decided by what is in the other one. See THE BOW.
- **Camera:** mouse / right stick; **scroll** zooms (kb+m only, see the swap above). **Esc**
  opens/backs out of the menu (pad
  **Start** toggles). Quitting is a menu row. The menu opens at launch; while it's up gameplay
  input is held and the world idles.
- **Lock-on (ER):** **R3** / **middle-mouse** toggles onto the foe nearest screen-centre; with
  none available R3 recenters. While locked the camera swings on, the hero faces it with REAL
  strafe/backpedal footing, a glowing white dot marks it, and a stick/mouse **flick** cycles
  targets — none of which happens while the bow is up (see THE BOW: aiming suspends it). Two deliberate ER
  exceptions: a hold-B SPRINT while locked faces TRAVEL (no sideways sprint exists), and an attack's
  recovery tail re-squares onto the target (`ATK_RETRACK`).
- Reserved, matching ER: Cross/A = jump. (**L2 is the AIM now**, owner's call — ER puts the skill there,
  and this build has no skills to put on it.)

## THE BOW (`hero.zig`) — the second right-hand armament

D-pad Right cycles the right hand between the sword and a bow. It is a straight SWAP, not a second thing
he holds: the bow goes in the same `HELD` slot on the right wrist, and the LEFT hand leaves the shield to
go to the string.

- **THE SHIELD GOING IS THE ANATOMY, NOT A BALANCE DIAL.** One hand cannot haul a string and hold boards.
  So it is `hero.canGuard` ASKING the arm rather than the swap clearing a flag — same shape as the guard
  itself, and it means the shield can never come back up while the bow is out however the swap happened.
  The HUD says so: the cross's RIGHT slot draws whichever armament is in hand and the LEFT one goes EMPTY,
  which is exactly what a raised bow costs you.
- **IT IS THE SKELETONS' BOW, down to the string.** `archer.bowMesh`/`stringMesh`/`nockArrowMesh` and
  `archer.poseBow` are shared, so a bow retune is still one file — and every angle of the hero's own stance
  is lifted from `archer.poseUpper`, which is a working full draw on this same 18-bone rig. Guessing them
  instead was the first attempt: it came back with the bow held across his chest and the string hauled
  down-and-forward, because the draw shoulder was half the angle it needed and the elbow a third short, so
  `poseBow` was lerping the nock toward a hand that had never left his hip. This is the one import that
  runs against the grain (hero.zig → archer.zig) and the reason is written at it.
- **THE AIM IS A HELD STATE, THE LOOSE IS THE ONLY COMMITTED ONE** — `setAim` is called every frame with
  the button's level and re-derives from `canAim`, so a roll, a stagger, a swap, a sprint or an empty bar
  drop it with no bookkeeping. The one committed action `canAim` deliberately ALLOWS is `shooting`: a loose
  out of a held aim must not cost him the aim, or the second shot of a pair is a different action from the
  first.
- **AIMING SUSPENDS THE LOCK OUTRIGHT** (`game.activeLock`), because that is what aiming IS — the stick is
  doing the pointing, and nothing may swing the camera, the reticle, his facing or a shot onto a foe you are
  no longer the one choosing. SUSPENDED, not dropped: the target is still there when the bow comes down, so
  aiming out of a locked fight costs no second press. R3 is dead while the bow is up for the same reason.
  An aimed shaft is thrown down the CAMERA's own forward (`BOW_AIM_REACH`), and a reticle marks it. A QUICK
  shot needs no aim and goes at the locked foe, else down his facing.
- **AND IT SLOWS THE LOOK** (`game.AIM_LOOK_SCALE`, eased on the same `aimB` blend, mouse and stick alike).
  The rate is not what changed: the eye sits at his head and the mark is thirty metres out, so a nudge that
  was a glance unaimed swings the shaft clean past a foe.
- **A BOW CHIPS; IT DOES NOT WIN** (owner's call). BOTH shots come in under the melee they compare to —
  the quick under a light slash, the aimed under a heavy — and the POISE on them is slighter still (an
  aimed shot staggers less than half what a heavy does). A shaft that hit like a sword would make closing
  the distance optional, and being paid for closing it is the shape of the whole game. Only the aimed shot
  touches stance at all. Behind a raised bow he moves at `BOW_AIM_SPEED` (0.45 of the walk,
  under the shield's 0.75): a shield is something you walk a fight down behind, an aim is something you
  stand still for.
- **ARROWS ARE FINITE** — `combat.Quiver`, ten of them, shaped like `Flasks` because it is the same thing:
  a small counted stack you spend in a fight and get back at a grace. An empty quiver REFUSES the shot with
  the same red flash a dry flask gets, and the quiver is checked BEFORE the stamina is charged — a loose
  that never happened must not bill him for it. The count lives in its own short box under the right-hand
  slot (ER's own place for it), and only while the bow is what he is holding.
- **AND THERE ARE TWO KINDS OF THEM** — plain, and the **FIRE ARROW**, cycled on **D-pad Up / Y** (Up
  because it is the cross's one empty slot, mirroring Down cycling the quick item). It is the game's ONLY
  source of non-physical damage: `hero.fireTipped` hangs fire damage worth `FIRE_ARROW_FRAC` (0.5) of the
  shaft's own physical ON TOP of it, PoE2's "adds X fire damage" — the physical is untouched, and the
  fraction rides the quick shot and the aimed one in proportion so the snapshot never becomes the better
  of the two. Five of them to ten plain (`combat.FIRE_ARROWS_MAX`), so it is a shot you choose a target
  for. See RESISTANCES.
  - **THE SELECTED KIND IS THE ONE THAT FLIES**, empty or not: a dry fire quiver refuses rather than
    quietly loosing a plain shaft you did not ask for.
  - **THE ARROW HE DREW IS THE ARROW THAT FLIES** (`Hero.shotArrow`). The shaft leaves a few frames after
    the draw, so the kind is LATCHED at `startShot` rather than read at the loose, and cycling is refused
    mid-loose besides.
  - **THE FLAME IS THE PROPS' FLAME** — `.flame` (emissive, translucent, guttering) and `propart`'s own
    fire palette, because a second kind of fire in one world reads as a different substance. Two things are
    its own: it streams BACKWARD down the flight axis instead of climbing +Y, and it is authored off a
    fixed seed so every shaft matches. **AND IT IS TONGUES, NOT A BLOB** — the first pass was two blobs and
    came back a faceted yellow lemon stuck on a stick; the HUD icon made the same mistake with a disc
    behind the pile and read as a ball. Both are tapered tongues trailing off the head now.
- **THE AIM PUSHES THE EYE IN PAST HIM** (`camera.AIM_DIST`, blended by `CamRig.aimB` off the hero's own
  stance blend) and **FADES HIM OUT** while it does (`game.AIM_FADE` → `gfx.Scene.setFade`). Two rules:
  the player's own `dist` is never written, so dropping L2 returns to the zoom HE chose rather than to a
  default; and the fade is LIT-PASS ONLY with the depth MASK off under it, because a translucent draw that
  still wrote depth would punch a hole in the flora behind him. It is the SECOND thing in the game allowed
  to be semi-transparent, after the flame.
- **THE SHOT CONVERGES ON THE RETICLE, it does not run parallel to it.** An aimed shaft is thrown at a point
  ON the camera's centre ray (`camera.centreRay` → `game.camAimPoint`), at the distance that ray actually
  REACHES — the nearest foe it crosses, else the ground it would land on. Aimed along the camera's FORWARD
  from the nock instead, the shaft flies a line parallel to the reticle's and offset from it by however far
  the bow is from the eye: the bow sits out on his right and the boom is shoulder-offset besides, so every
  shot ran a constant half-metre-odd to one side at every range. And the LOFT is only added when the target
  is a real point, because it is solved against that distance (see `archer.launchAt`).
- **HIS SHAFTS ARE A PIERCING BLADE** (`foe.Blade.pierce`). The segment one crossed this frame goes
  through each creature's own `tryHit`, so an arrow bleeds, flinches, staggers and kills exactly the way
  the sword does instead of a second reaction path written four more times. It neither reads nor writes
  the swing LATCH, and both halves matter: reading it would let a foe still latched from the last cut
  swallow an arrow, writing it would let an arrow eat the sword's next hit. It needs no latch of its own —
  the shaft is spent on the first thing it reaches.
- **`archer.stepShaft` is `stepArrow` with the two hero-specific halves removed**: no homing (it goes
  where he aimed it; a shaft that curved onto a target would make aiming decoration) and no target test,
  because what this one flies at is a field of foes rather than the one hero. It hands back the SEGMENT and
  the caller sweeps it. Cover, gravity, the ground and expiry are the same, so his arrows thunk into the
  pillar he shoots past exactly as theirs thunk into the one he ducks behind.
- Shots `20f`..`20r`: the carry (no shield on that arm), the aim from three bearings, a CROP of the string
  and nocked shaft, the loose on the frame the string snaps home, the quick shot's own raise, a shaft in
  flight, the HUD cross, the AIM CAMERA with him faded out under it, and the quiver both full and dry.
  `20s`..`20u`: a FIRE shaft in flight in the plain one's exact framing so the two streaks are comparable,
  the burning head cropped from the FRONT QUARTER (side-on is mostly trail, with the head buried in it),
  and the ammo box carrying the other arrow.

## RESISTANCES (`combat.zig`) — PoE2's four, and physical is what we already deal

Damage is TYPED. A `Hit` carries physical `dmg` plus an optional `elem` bundle (`combat.Elems`), and
`Vitals.hit` puts each element through the body's own `Resists` on the way in. Every blow authored before
this exists is pure physical and its arithmetic did not move.

- **PHYSICAL IS NOT ONE OF THE FOUR.** `Elem` is fire / cold / lightning / chaos, exactly PoE2's, and what
  mitigates physical there is ARMOUR — which does not exist here yet, so physical arrives whole. Do not
  quietly add a "physical resistance" to the table; the day armour lands it is its own curve
  (`A/(A + 5*dmg)`), not a fifth percentage.
- **75 IS THE CAP, AND NEGATIVE AMPLIFIES.** `RES_CAP` 75 % however much is stacked, `RES_FLOOR` −100
  (exactly double damage). Stored UNCAPPED and capped on READ (`Resists.at` vs `.raw`), so a creature
  authored at 90 still reads 90 on a sheet while taking damage at 75 — PoE2's own split.
- **A SPREAD IS WRITTEN BY NAME** — `combat.resists(.{ .fire = -45, .cold = 20 })`. The field names are
  matched against the enum at comptime, so a rename is a compile error and an omitted element is a 0. An
  array literal in enum order is how a four-wide row silently shifts the day there is a fifth element.
- **POISE AND STANCE BELONG TO THE BLOW, NOT THE BODY.** A creature that shrugs off the fire still flinches
  from the arrow. And the shield's chip (`guardChip`) is DAMAGE ONLY for the same reason from the other
  side — it returns a `Hit` now, so the chip's elemental share meets the blocker's resistances instead of
  arriving as raw HP, but it carries none of the stagger the guard exists to eat. That is what the block
  test caught: scaling the whole hit put the blow's full poise through a raised shield.
- **A SHIELD IS BILLED ON THE RAW BLOW** (`Hit.raw`, physical + every element, unresisted) — the arm behind
  a burning arrow does not know what you resist. Same for `foe.worseBlow`'s "which of these was worse".
- **TWO OF THE FOUR ARE LIVE.** **FIRE** — the hero's fire arrow, and the kobold sling's burning clump.
  **CHAOS** — the brood mother's spit AND her pools, which are one fluid and so one element (owner's
  call). Cold and lightning have no source yet and every table that carries them says so.
- **EVERY FOE CARRIES ITS OWN, AUTHORED WHERE ITS HP IS** (`initFoe(..).withRes(..)`), one table per
  creature and per FILE — the kobold's three roles share one because they are one creature, and so do the
  brood mother and her hatchlings, at two ages:

  | creature | fire | cold | lightning | chaos | why |
  | --- | --- | --- | --- | --- | --- |
  | gaping toad | +40 | −30 | −25 | 0 | wet out of a bog; cold-blooded, and wet conducts |
  | skeletal archer | −35 | +60 | 0 | +45 | dry bone burns; no flesh to freeze or to poison |
  | one-eyed ogre | +30 | +30 | −15 | +20 | too much mass for any of it, but it stands in an open field |
  | kobold (all three) | −45 | +20 | 0 | 0 | fur goes up — the fire arrow IS the answer to a warband, and they throw it themselves |
  | brood mother / broodling | −25 | +35 | 0 | +75 | chitin and its own acid, hung about with silk |
  | egg sac | −70 | 0 | 0 | +75 | dry silk over a membrane: the one thing in her nest that really burns |
  | skeletal warrior (both) | −35 | +60 | 0 | +45 | THE ARCHER'S OWN TABLE, because it is the archer's body |

- **NOTHING GRANTS THE HERO ANY YET, AND THE SHEET SAYS SO ON ITS OWN ROWS** — Character menu >
  **RESISTANCES**, a second read-only list beside ATTRIBUTES, rows walked off `combat.Elem` so a fifth
  element is on it the moment it has a name. It shows all four at **0%** on purpose (owner's call: show
  them even at 0), each with a footnote saying what deals that element and that nothing grants any yet —
  `combat.elemSays`, which is `stats.governs` for damage types and rots the same honest way. The value
  column prints the STACKED number with the CAP beside it when they differ (`90% (75%)`), PoE2's own
  display. `makeWhole` CARRIES RESISTANCES ACROSS a grace: they are what he is, not a meter to refill, and
  rebuilding the vitals from the sheet would silently wipe the first ring that ever grants one.
- **AND THE DEBUG ROW READS THE LOCKED FOE'S** (`game.foeResists`), alongside which arrow is on the
  string — the four are most legible against a named target.

## PERFORMANCE: how a 560 m world stays cheap (`env.zig`)

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
- **THE FLAME MATERIAL IS THE ONE THING DRAWN SEMI-TRANSPARENT BY ITS MATERIAL** (owner's call; the HERO under an aim is the one thing drawn semi-transparent by a per-draw `fade` uniform — see THE BOW), and its opacity is
  GRADED off that same emissive: `FLAME_A_CORE` where a tongue is hot enough to hide what is behind it
  down to `FLAME_A_TIP` at the cool tip, which is already the ramp `flameInto` authors. Depth WRITE
  stays on, so a flame blends over what was drawn BEFORE it (ground, water, its own ironwork) and its
  overlapping tongues do not stack into a brighter core; a prop drawn later and standing behind one is
  still occluded, which at a torch's size reads as nothing and is far cheaper than sorting the prop
  pass. The flame still casts a solid shadow — the depth pass has no colour and no alpha.
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
  around the horizon, reads as a periodic pattern. Yaw and scale do not hide it. The three `bigtree`
  kinds and the six `CLIFFS` exist for this — a scatter draws among them through its op's WEIGHTED
  `mix=` — and long-wavelength variation beats per-instance noise.
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
  and leak at exit — fine). Don't `unloadModel` them. The TERRAIN TILES are the one exception — they
  are re-authored as you sculpt — and getting there cost two separate crashes worth knowing about:
  - **`gfx`'s mesh allocator MUST be `raw_c_allocator`, not `c_allocator`.** raylib frees mesh CPU
    arrays with libc `free()`, and `std.heap.c_allocator` does NOT hand out malloc pointers on Windows
    (no `posix_memalign` → it over-allocates and hides the original pointer in a header BEFORE the
    aligned address). Freeing one with C `free()` frees an interior pointer: heap corruption, surfacing
    as a `0xC0000374` exit with no stack in it.
  - **`rl.unloadModel` UNLOADS THE MATERIAL'S SHADER.** The shader on a terrain tile is the SCENE
    shader every other draw uses, so unloading one tile deletes the program out from under the whole
    renderer and frees its uniform table — and the next tile frees the same pointer again. Go through
    `env.unloadTerrain`, which points the material at raylib's default shader first.
- **GLSL RESERVED WORDS ARE NOT ONLY THE OBVIOUS ONES.** A local named `patch` (the tessellation
  qualifier) compiled everywhere the author tested and failed on Intel, which enforces it even at
  `#version 330` — and a scene shader that fails to compile is a hard panic at startup with nothing but
  "syntax error" and a line number. `layout`, `subroutine` and friends are the same trap.
- **raylib's `SetSoundPan` IS THE LEFT CHANNEL'S GAIN, not a left-to-right position.** Its mixer is
  `left = pan; right = 1 - pan` (`raudio.c`'s `MixAudioFrames`), so **`pan = 1.0` is hard LEFT** —
  the opposite of the obvious reading, and raylib's own header says only "(0.5 is center)" without
  saying which end is which. Writing the natural `0.5 + width*side` mirrors every positional sound in
  the game, which is what it did until `audio.panFor` was fixed; that one function is now the only
  place the sign is decided, and a test pins it. Note also that the pan law is `0.5·x·(3 − x²)`, so a
  hard-panned sound is ~3.2 dB LOUDER in its own ear than a centred one is in either — which is why
  the two-channel wind bed needed its gain pulled down when it was widened.
- **Never bulk-edit source through PowerShell** `Get-Content`/`Set-Content`: em dashes mojibake
  and a BOM appears. Use the Edit tool.

## Next steps (not yet built)

**Criticals** off a stance break (the stagger already exists), hyper-armor windows during the
hero's own attacks, and the **GUARD COUNTER** (block → immediate R2: modest bonus damage, stance
damage like a charged heavy — the "block, punish, stagger" loop). Plain guarding, its stamina cost
and the guard break are BUILT (see GUARDING); the counter and the parry are what is left of ER's
left hand. AR × motion-value × defense damage (today it's flat constants), **status buildup**,
jump, distinct combo follow-up anims, bonfires, real level geometry. See `docs/ELDEN_RING.md` for
the target mechanics behind each.

Elevation exists but nothing has been AUTHORED with it yet: the shipped map is flat on purpose, and
there is no FALLING — walk off a lip and you are eased down it at `GROUND_FALL_RATE` rather than
dropping, because there is no airborne state for the hero to be in (jump is unbuilt for the same
reason). Terrain does not cast shadows, and painted water is still one level plane, so a lake is a
basin you dig rather than a pool at any height.

Current gaps: the roll has front-loaded i-frames (0→0.46 s of 0.70 s, gating `takeHit` + the
arrow connect) but still **no collision**; there is **no foot IK** — `rx(bodyPitch)` in
`hero.pose()` rotates the body about the WORLD ORIGIN, not the support foot, so under a deep lean
a forward-swung foot is levered down (walking and pure sidesteps are exact; a diagonal keeps
~6 cm), and on SLOPED ground the same absence shows as feet clipping a few cm into the hill, since
each sole is levelled against a flat `SolePatch` plane rather than the terrain under it.
One leg-cycle is reused across run and sprint, and attacks reuse one anim standing or
moving.
