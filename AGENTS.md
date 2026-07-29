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
**`docs/ELDEN_RING.md`** as the systems reference). **STAMINA is live but does not LOCK OUT** —
the roll/swing bites and the sprint bleed all run at ER's own numbers, and `combat.STAM_LOCKOUT`
switches the "empty = can't act" half on when the owner wants it. No criticals, guarding or jump
yet. The bar for "human" is anatomy + real gaits, not polygon count.

**THE HUD IS ELDEN RING'S**, in ER's three places and nowhere else: HP/FP/stamina bars top-left,
the four-slot equipment CROSS bottom-left, the debug readout top-right (menu >
Debug > Stats). It hides behind the menu and under the YOU DIED card. FP is a full static bar —
there is nothing to spend it on until spells exist.

**THE WORLD** is a 320 m square golden-hour plain ringed by cliffs, holding five regions
(see `env.zig`'s header for the map, `props.zig` for the models):

| Direction | Region | What's there |
| --- | --- | --- |
| centre / south | the fallen avenue | colonnade, gate arch, grace ember, the start |
| north | **the Fallen City** | plaza, walls, ruined house shells, a torchlit **chapel you walk into**, two **watchtowers** with dark ground rooms, carts, the colossal horizon gate |
| east | **the Tarn** | a shallow lake you **wade**, drowned columns, a collapsed causeway, willows, reeds |
| west | **the Old Wood** | great trees (3 variants), ferns/brambles/bushes, boulders, a **standing-stone circle**, a woodcutter's **cottage** + campfire |
| south | **the Windswept Downs** | open and sparse — lone trees, field stones, graves, a watchtower |

**77 prop kinds**, 7,876 instances and 1,575 colliders, of which a frame draws ~1,000 across both
passes (measured: 985 in the city, 1,059 in the wood). See **PERFORMANCE** — that ratio is why the
world is affordable, and the debug Stats overlay prints it live so it stays checkable.

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
  the cliffs, five overhead MAP shots and two Stats readouts. Never claim a visual change works
  without a shot. `shots\` is gitignored. Do NOT launch the interactive window to "check" — the
  owner plays the real game himself, and while he has it open the build cannot overwrite the exe.
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
- `env.zig`    — THE WORLD: the ground plane, the five regions AUTHORED IN CODE (a region is a
                 paragraph you can read, not a table of coordinates), the seeded ground-cover
                 scatter + `coverField`, and the three systems that make this size affordable —
                 the UNIFORM GRID, the CULLERS (`View`/`Cull`), the grid-local solid queries.
                 Also gathers each fire's `gfx.Light` and uploads the nearest per frame.
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
                 ONCE. Holds `Blade` and `strike()`.
- `combat.zig` — SHARED `Vitals`: HP + the two-tier stagger + regen + death. Plus `Stamina`,
                 the HERO'S ALONE (a foe meter nothing reads would only rot). Pure logic,
                 unit-tested. THE place to retune damage/poise/stamina feel.
- `collision.zig` — 2D XZ capsule/circle footprint collision (push-out).
- `mathx.zig`  — ground-plane + vector/angle helpers.
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
  `totalHits` / `aliveCount`; game.zig iterates groups generically.

## Combat feel

- **The two sides are tuned SEPARATELY** (`combat.zig`). A stagger you inflict is a punish WINDOW
  you must be able to walk into and use; a stagger you suffer is time taken off the player, which
  the FEEL RULES spend as little of as possible. Hence `FOE_LIGHT_STUN_DUR` / `FOE_HEAVY_STUN_DUR`
  well past the hero's, and `FOE_REGEN_DELAY` / `FOE_REGEN_RATE` far slower — a foe whose poise is
  back before your next swing can only be staggered by a burst, and every fight collapses into
  "land two fast or don't bother".
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

Stamina LOCKOUT (the meter is live; `combat.STAM_LOCKOUT` gates ER's "empty = can't
roll/attack/sprint"), **criticals** off a stance break (the stagger already exists), hyper-armor
windows during the hero's own attacks, guarding + **guard counter**, AR × motion-value × defense
damage (today it's flat constants), **status buildup**, jump, distinct combo follow-up anims,
bonfires, real level geometry. See `docs/ELDEN_RING.md` for the target mechanics behind each.

Current gaps: the roll has front-loaded i-frames (0→0.46 s of 0.70 s, gating `takeHit` + the
arrow connect) but still **no collision**; there is **no foot IK** — `rx(bodyPitch)` in
`hero.pose()` rotates the body about the WORLD ORIGIN, not the support foot, so under a deep lean
a forward-swung foot is levered down (walking and pure sidesteps are exact; a diagonal keeps
~6 cm). One leg-cycle is reused across run and sprint, and attacks reuse one anim standing or
moving.
