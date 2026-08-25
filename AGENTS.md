# AGENTS.md — zig-soulslike

Third-person soulslike in **Zig 0.14.1 + raylib**, on the sibling `../zig-rts` engine (procedural-mesh
`Builder`, single-sun shadow-map pipeline). README covers what exists.

`docs/ELDEN_RING.md` is the systems reference and is **PURE Elden Ring** — real mechanics, real numbers,
nothing about this game. Our own mechanics and tunings go here, in the README, or in the code.

Keep this file lean. Prefer no comments in code — succinct ones for novel/edge cases only. Reuse existing
helpers before adding code. Don't make ad-hoc product/design decisions: ask. The owner drives the design;
implement what's asked and nothing extra. Don't commit, push, or create branches unless explicitly asked.

## The laws (owner's, non-negotiable)

- **NO HITSTOP. EVER.** No freeze-frames, no time-dilation on impact, no dt zeroing. Impact weight comes from
  shake + rumble + FX + huge reaction anims.
- **NO INPUT READING. EVER.** No creature may branch on the player's INPUTS or committed actions — not the
  flask, not a cast, not a roll, not an attack press. A decision may read POSITION, BEARING, DISTANCE and ITS
  OWN CLOCKS — the world as any body standing in it could see it — never the hero's state machine.
- **ZERO INPUT LAG.** The stick maps straight to ground speed every frame. Posture/gait blends may smooth the
  VISUALS only, and only fast (~0.1 s max).
- **REACTIONS ARE HUGE.** A flinch or stagger must be big and obvious. **A mass in motion OVERSHOOTS its rest
  and settles back onto it** — props and geometry included; a glide to a stop reads as weightless.
- **FLESH IS ROUND.** Organic mass = `addBlob`/`addCapsule`; `addCube`/`addBox` is for iron, blades, cloth,
  masonry. Bare `addCylinder` leaves an open cut-pipe end.
- **BIG BODIES HINGE AT THE WAIST, LEGS STAY PLANTED.** Route lean through SPINE/CHEST, pelvis near-upright
  (`ogre.PELVIS_SHARE`); lean at the ROOT rotates the legs and reads as lurching. Braces take up in the knees.
- **WABI-SABI is the house style for ALL art.** Uneven sizes, asymmetry, leans, gaps, authored with a seeded
  `mathx.Rng` so builds stay deterministic. Reads "dumb"/fake ⇒ almost always too REGULAR. Cosmetic only.
  **AT THE RIGHT SCALE: BETWEEN the instances, not ALONG one** — two tones alternated segment by segment band
  a shaft like a barber's pole; the same two separating the VARIANTS read as three kinds of wood.
- **NOTHING DEAD IS STRAIGHT, AND NOTHING ENDS IN A POINT.** A dead limb leaves the bole on its axis, rises to
  an elbow, DROOPS off the line to a blunt snap of pale heartwood; twigs root on that outer half.
  `propwood.deadLimbInto` is the one both leafless trees call.
- **RELIEF IS SUBTLE.** A few PERCENT of the mass's radius, not a tenth. Sink the proud primitive most of the
  way in. Prefer more SIDES on the mass over more relief on top. Judge against the ASSEMBLED thing. Cut
  AMPLITUDE, never irregularity.
- **PACKED STONE HAS A CORE.** A row of blocks is only the FACING; without a substrate the joints leak sky.
  Overlap well past the slot — `propart.courseInto`/`courseStack` do both.
- **DENSITY VARIES.** A flat per-region density is a carpet. `env.coverField` (two octaves of value noise)
  scales the region constant to nothing in clearings, and gates the structure belts.
- **A REGION NEEDS THREE LAYERS** or it reads sparse: ground-hugger, understorey, canopy. Dead growth is what
  stops it looking like a garden.

## Build & verify

- `zig` is NOT on PATH. Build with `build.cmd` / `build-release.cmd`; toolchain is
  `..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe`. `zig build test` runs unit tests.
- Verify rendering/animation by RUNNING `zig-out\bin\zig-soulslike.exe --shot` (or `shot.cmd`) and inspecting
  `shots\` (gitignored). Never claim a visual change works without a shot.
- Do NOT launch the interactive window to "check" — the owner plays it himself, and while he has it open the
  build cannot overwrite the exe. Build with `--prefix zig-out-dev` when locked.
- `--shot-props` renders every kind alone into `shots\props\`. For ONE model the editor's object viewer is
  faster.
- **Framing is part of the test.** Confirm the camera SHOWS the moving part before tuning. `follow` does not
  clamp pitch, so a small negative pitch at long `dist` puts the camera under the terrain; the camera ends at
  `target + back*dist`, so interior framings must be DERIVED from the room's extent; the shadow ortho box
  tracks the HERO, so `standHero` near your subject. For a world change take a steep overhead (`dist` ~55).
- **A SUBJECT MUST BE LIT, NOT JUST IN FRAME.** `gfx.SUN_DIR` puts the sun over the shoulder of a camera at
  **yaw ≈ 53** and into the lens of one at **≈ 233**. A foe turns to face the hero, so "photograph its front"
  means putting the sensed hero on the SUN's bearing and shooting from ~53; the 180–215 band shadows its front.
- **Thin geometry needs a CROP.** Strings, nocked arrows, flutes, setts and HUD rims are invisible at 1:1.
  Nearby clutter can masquerade as the part you are looking for.
  ```powershell
  Add-Type -AssemblyName System.Drawing
  $src=[System.Drawing.Bitmap]::FromFile("$PWD\shots\40_x.png")
  $crop=$src.Clone((New-Object System.Drawing.Rectangle 460,360,300,220), $src.PixelFormat)
  $big=New-Object System.Drawing.Bitmap 900,660; $g=[System.Drawing.Graphics]::FromImage($big)
  $g.InterpolationMode='NearestNeighbor'; $g.DrawImage($crop,0,0,900,660); $big.Save("$PWD\shots\crop.png")
  ```
- **JUDGE ALBEDO BY SAMPLING THE RENDER, NOT BY EYE.** Chain is albedo × 1.72 → linear → gamma 1/2.2. Screen ∝
  albedo^(1/2.2), so a factor you want on screen is that factor^2.2 on the albedo — solve, don't guess, and
  `GetPixel` the subject AND what it stands against. Separate on HUE as well as value: everything outdoors
  here is warm.
- **THE SCREENSHOT GOES BEFORE `endDrawing`, NEVER AFTER** (`shots.snap`) — `endDrawing` swaps buffers, so
  after the swap every capture is the previous frame.
- **The harness CLOSES THE MENU first** (`runShots`); the menu opens at launch and the HUD hides behind it.
- `--shot` PNGs are not byte-deterministic (flora wind + grain read `rl.getTime`) — verify visually, never by
  hash-diff.

## Module map

`src/` is in directories: `core/` (maths, collision, the pose kernel, the camera, audio, rumble, the bake
door), `gfx/` (builder + scene + GLSL + the element particle language), `world/` (terrain, the map format, the
clock, the weather, triggers, dialog), `props/`, `foes/`, `play/` (the hero and his sheet), `ui/`. The loop, the
entry, the slot and the shot harness stay at `src/` itself. An `@import` is a path from the importing file —
`../core/mathx.zig` — and `main.zig`'s test block names each module by that same path, which `build.zig`'s
roster check walks the tree to enforce.

**How files are divided:** minimise TOKENS TO MAKE A CORRECT CHANGE, not file size. A 900-line file whose
contents change together is fine. Splits go where concerns genuinely part company.

| file | what |
| --- | --- |
| `main.zig` | entry; `--shot` headless harness |
| `game.zig` | window/loop, input, camera-relative movement, render orchestration, combat beats, YOU DIED |
| `play/hero.zig` | THE HERO — FK skeleton, every animation, swept blade capsule, guard, bow, wand. Start here |
| `core/anim.zig` | THE KEYED-POSE KERNEL — `Ease`/`Key`/`keyAt`, `Spring`/`SpringBank`, `anim.Pose(P)` |
| `foes/behave.zig` | `Routine` (close/open/orbit/dwell/shift) + named scripts (`DISENGAGE`/`FLANK`/`KITE`) |
| `core/camera.zig` | orbit rig, ground basis, trauma shake (live-loop only, so `--shot` stays deterministic) |
| `gfx/gfx.zig` | mesh `Builder`, scene shader, shadow depth pass, `Sky`, `Vignette`, `Mat` materials |
| `gfx/shaders.zig` | every line of GLSL and nothing else; the contract with `gfx.zig` is at its top |
| `gfx/elemfx.zig` | the elements' particle language — one signature per `combat.Elem`, `gather`/`burst`/`pour` |
| `world/daynight.zig` | the world clock — sun/moon path, the hour's palette, the anchor hour `--shot` pins |
| `world/weather.zig` | intermittent rain in two strengths, lightning, the one rain mesh, the mist banks |
| `world/worldfmt.zig` | THE MAP FORMAT — ops, zone/foe/npc/trigger/dialog tables, one comptime field table |
| `world/trigger.zig` | SC1's conditions + actions, and the switches / counters / timers they compose through |
| `world/dialog.zig` | one conversation: the node-tree walk and the BG2-style panel, with a live portrait |
| `world/env.zig` | THE WORLD — terrain, op replay, `coverField`, uniform grid, cullers, occluder fade, lights |
| `props/props.zig` | prop vocabulary + the `INFO` table; `displayName`/`group`/`stock` are exhaustive switches |
| `prop*.zig` | meshes by family — `propart` (palette + weathering), `propruins`, `propgold`, `propbuild`, `propvillage`, `propmarket`, `proprock`, `propwood`, `propflora`, `propfungus`, `propcoral`, `propash`, `propbone`, `propfx` |
| `foes/foe.zig` | THE FOE STANDARD — contract, `Blade`/`strike`/`weaponReaches`/`Blow`, `Trail`, particles, `Leash` |
| `foes/npc.zig` | the wanderer, on the hero's scaffold; idle set, gestures, roam, staff that plants with the far foot |
| `foes/frog.zig` | gaping toad + `Knot` |
| `foes/archer.zig` | skeletal archer + `Line`; kite-only, arrows that stick and fade |
| `foes/ogre.zig` | one-eyed ogre + `Grief`; 24 bones, high poise, slam / swipe / drive; never strafes |
| `foes/kobold.zig` | warband + `Warband` — berserker/priest/slinger; the priest is why they are one group |
| `foes/brood.zig` | brood mother, sacs, broodlings + `Brood`; guard not hunter, venom POOLS poison |
| `foes/warrior.zig` | skeletal warriors + `Muster` — shieldman (blocks, guard-breaks) and greatsword (hyper armour) |
| `foes/knight.zig` | THE BONE KNIGHT + `Vigil` — first boss, first boss bar |
| `foes/shade.zig` | shades + `Haunt`; legless, hovers, 17 bones. Drains FOCUS; the one thing that TELEPORTS |
| `foes/leechfly.zig` | first FLYER + `Swarm`; never lands, drinks HP and heals off it, zooms out of sword reach |
| `foes/rooted.zig` | snag-mimic fixture + `Grove`; eyes open outside its reach, three limb strikes, never moves |
| `foes/shroom.zig` | sporeling + `Cluster`; flings itself, bursts a spore cloud that poisons. Sometimes TRIPS |
| `foes/delver.zig` | THE DELVER + `Warrens` — goes UNDER; bursts underfoot or ploughs a furrow. No lock-on while down |
| `foes/necro.zig` | THE NECROMANCER + `Rite` — holds a corpse open and raises it once; the only COLD source |
| `foes/wolf.zig` | first SPIRIT + `Pack`, what the BELL calls. NOT a foe; first QUADRUPED, 27 bones |
| `foes/ravager.zig` | florid ravager + `Thicket` — quadruped rig's second user + 4 petal bones. The BLOOM is the tell AND the window |
| `foes/shroommage.zig` | mushroom mage + `Ring` — the fireball BOUNCES, so it punishes backing off |
| `foes/fenlurker.zig` | fen lurker + `Marsh` — never leaves the water; sunk it is unreachable. Counter is DRY LAND |
| `foes/sporegolem.zig` | spore homunculus + `Host` — `ARMOUR` is the creature; fire and lightning pass through |
| `foes/skitterer.zig` | bone skitterer + `Clatter` — walks ON ITS RIBS; the eye SHUTS before the spine slams. What a priest raises |
| `foes/ancientpriest.zig` | ancient priest + `Crypt` — never melees; claws a skitterer out of bare earth far off, breathes COLD close |
| `foes/hollow.zig` | tolling hollow + `Belfry` — the BELL on its back calls every body inside `TOLL_R`; refused inside bite reach |
| `foes/slumberbloom.zig` | slumber bloom + `Bed` — a rooted FIXTURE with no blow at all; the only SLEEP source, and it cannot follow |
| `play/combat.zig` | `Vitals`, `Stamina`, `Focus`, `Regen`, guarding rules, `HitOutcome`, `Elem`/`Resists`, spirits. THE place to retune feel |
| `play/stats.zig` | the sheet — seven attributes, the bar curves, the ONE skill curve (`scaleFor`), `inert` |
| `play/passivetree.zig` | PoE2's tree radially: three arms out of one hub, the gates, `Bonus`, the wheel |
| `play/item.zig` | item vocabulary, `Use`, **`Equip`/`Wear` (the GEAR table)**, the `Bag` |
| `play/chest.zig` | openable boxes; contents read off the placing op (`Op.loot`) |
| `play/rest.zig` | bonfire + campfire — phase machine, the seat, the fire's own screen; `isRestKind` |
| `play/souls.zig` | THE DROP — what a death leaves, the gold bloom, the walk back |
| `play/drops.zig` | one row per `FoeKind`, guaranteed + rare, and **the one thing LUCK reads** (rare weight only) |
| `play/pickup.zig` | the glow a drop stands as; `REACH` 2.4, between `chest.REACH` 2.1 and `souls.REACH` 2.6 (`rest.REACH` 3.2 is the widest) |
| `play/award.zig` | the FIRST-TIME card and the toast strip; `seen` is what makes a kind new, and `carding` holds the world clock |
| `ui/hud.zig` | ER HUD, the pad-glyph kit, the day dial, the boss bar, and the ONLY path to draw/measure text |
| `ui/ui.zig` | editor widget kit; `Ctx.anyHot` gates world clicks next frame |
| `ui/uiart.zig` | chrome DRESSING shared by hud/menu/book/ui |
| `ui/itemart.zig` | pictures of things — armaments and bag items as objects, sized by the caller |
| `ui/icons.zig` | editor glyph set, drawn from primitives (vector, not an atlas) |
| `ui/book.zig` | THE CHARACTER BOOK (pad START) — paper doll + ten quick sockets, the bag, the sheet |
| `ui/menu.zig` | boot screen, pause/debug menu, sound LEVELS, retro filter rack |
| `ui/editor.zig` | THE EDITOR (Menu > Editor), layered StarEdit-style; biggest file, next split candidate |
| `ui/objview.zig` | object viewer + the JUKEBOX + the FX BENCH (`elemfx`'s cells with their numbers printed) |
| `save.zig` | THE SLOTS — three files in the map's own `key: value` grammar, each with its picture |
| `core/audio.zig` | ~80 synthesized voices through one tape-style `master`; three submixes; read as recipes |
| `core/rumble.zig` | XInput directly (raylib's GLFW backend stubs `SetGamepadVibration`); holds `PAD` |
| `shots.zig` | the headless harness — never in context while working on the loop |
| `core/collision.zig` | 2D XZ capsule/circle push-out, `blocksSight` |
| `core/mathx.zig` | ground-plane + vector/angle helpers, seeded `Rng`, `gutter` |
| `core/bake.zig` | one-way door that emitted the first map from the old code-authored regions |

Two things in that table are load-bearing beyond navigation:

- **A DEFAULTED FIELD ON `Game` MUST BE ASSIGNED IN `init`.** It is built from `alloc.create`, so `= .{}` on the
  field never runs and it comes up as the fill byte. Silent, and it has bitten twice: `pack.n` as garbage, and
  the whole day/night cycle dead because `g.day` was never assigned (rate 0 is a held clock; a NaN hour renders
  as the anchor).
- **THE LIVE PORTRAIT IS TWO CALLS AND THE SPLIT IS LOAD-BEARING**
  (`hud.renderPortrait`/`blitPortrait`/`livePortrait`, the one way a body is photographed into the UI).
  `endTextureMode` restores the DEFAULT framebuffer, not the target bound before it, so a render nested inside
  `hud.beginChrome`'s target silently sends the whole rest of the frame at the backbuffer. Render BEFORE the
  chrome opens, blit inside. The ANGLE is the house's (`hud.PORTRAIT_*`), the DISTANCE the subject's.
- **`elemfx`'s SIGNATURE IS THE MOTION**: fire RISES and alone leaves a residue, cold FALLS and lies about (the
  longest life by 2×), lightning DOES NOT TRAVEL (the shortest by 3×, the only colourless one), chaos goes
  INWARD. Tests tell the four apart with the colour taken away, and again on hue alone.
- **A BLOW STOPPED ON A FOE'S SHIELD HAS ITS OWN VOICE** (`foe_guarded`, `knight_repel` one size up for the
  wall). `guard_block` is the HERO's shield eating a blow — the opposite event.

## The hero rig (`hero.zig`)

- **Anatomy is real.** Bone lengths are fixed fractions of stature `H` (=1.8), Drillis & Contini via Winter.
- **18 bones** (`hero.N` — 17 joints plus the SWORD on the right wrist). `pose()` chains a world matrix per
  bone ONCE per frame; `draw()` only replays them, so shadow and silhouette always match.
- **Matrix convention (critical):** raylib `MatrixMultiply(a, b)` applies **a FIRST, then b**. Local =
  `mul(animRot, translate(offset))`; world = `mul(local, parentWorld)`. Backwards and the skeleton explodes.
- **Gaits are real.** Walk uses normative sagittal curves (Perry/Winter); run/sprint use Novacheck. Phase is
  driven by DISTANCE travelled, never time, so feet never skate.
- **THE 18-BONE SCAFFOLD IS SHARED** — `hero.N`/`PARENT`/`restHumanoid(hx, sx, stature)`, bone 17 the `HELD`
  weapon slot. Do not transcribe the joint layout into a new creature file. Only `hx`/`sx` and stature are
  honestly per-creature. The ogre stays off it on purpose (24 bones, three inserted ABOVE existing joints).
- **A SCALE≠1 humanoid must scale its pelvis HEIGHT** (`pelvY*fs`) or the legs sink.
- **EITHER HAND MAY HOLD ANYTHING, AND THAT IS THREE THINGS PER ARMAMENT, NOT ONE** (`hero.Armament`): the
  MESH (`drawHand`), the POSE of the arm, and every WORLD POINT taken off it. All three ask one question —
  `handsHold` / `meleeLeft` / `wandLeft` / `shieldLeft` / `torchLeft` / `bellLeft` — and a pose picks its side through
  `armSide(left, authoredLeft)`, whose `mirror` multiplies the LATERAL channels (`ry`, `rz`) and leaves
  sagittal `rx` alone. Miss the third and it fails INVISIBLY: a rod equipped right drew and carried perfectly
  and threw every bolt out of the empty left fist, because `wandTipWorld` was still `xf[WRL]`. Same shape on
  the boards (`shieldFaceWorld`, guard, parry) and on the bell, mirrored.
  **AND A TWO-HANDER CLAIMS BOTH HANDS FROM EITHER SLOT** — asked as "is the RIGHT slot two-handed", a bow in
  the LEFT left a shield in the right blocking and parrying.
- **THE THREE MELEE CLASSES ARE THREE ARMAMENTS, EACH WITH ITS OWN SOCKET AND ITS OWN TWO STROKES** —
  `sword`/`dagger`/`club`, `hand_sword`/`hand_dagger`/`hand_club`, and `hero.MOVES` indexed `[Blade][heavy]`.
  R1 and R2 are the whole kit — no strings — and the six are `slash`/`chop` (the sword's, hand-tuned),
  `flick`/`thrust` (the dagger: DS1's rapid jabs, and the R2 that thrusts), `sweep`/`smash` (the club: DS1's
  dashing horizontal swing, and the OVERHEAD SMASH).
  - **THE WEAPON HAND IS ONE HAND** (`handsHold`, `offInHand`). The rig has ONE held bone, so two live melee
    cells would draw one of them nowhere. The RIGHT cell wins, as a two-hander wins over the cell it did not
    fill, and `offInHand` says so in words the book can print.
  - **THE FOUR NEW STROKES ARE KEYED TRACKS** (`MK`, `anim.Pose`, `poseStroke`) — one rig function, four key
    tables. NO SPRING BANK: `pose` takes no `dt` (every hero pose is pure in its own clock, which keeps
    `--shot` reproducible), so load, HANG, snap, carry-past and settle are authored as KEYS.
  - **AN ARRIVAL IS `.accel` INTO THE BLOW AND `.decel` OUT OF IT, NEVER `.snap`.** `snap` is front-loaded, so
    on a strike key it puts the whole stroke BEHIND the capsule: measured, the dagger crossed 13° of its 84°
    arc inside its own live window and the club was already on the ground when the window opened.
  - **A CLASS'S ROW IS `item.DAGGER`/`item.CLUB` AND ITS WEAPON *IS* THAT ROW** — one set of numbers. Neither
    class is offered BARE in the book; `bareArm` exists so an emptied socket is sane, not reachable.
  - **`item.Wear` IS APPEND-ONLY, AND THAT IS NOT ENOUGH ON ITS OWN.** A save's `worn:` run is positional over
    that enum; the KIND now names its own socket and the position is only a cursor, so a re-socketing cannot
    make the loader throw out a real file.
- **HUMANOID ENEMIES REUSE THE HERO'S WALK/STRAFE** — `hero.advanceGait` + `hero.legChain`. Never author a
  bespoke walk; only the upper body is per-enemy. `legChain` is rig-size agnostic but a foe rig must keep the
  hero's leg indices (5..10) where they are.
- **THE UPPER BODY MUST ARTICULATE TOO — legs alone are not a gait.** Every walking humanoid owes a
  contralateral arm swing at full amplitude, elbows flexing through the forward half only, a shoulder girdle
  counter-rotating against the pelvis (`prot`), a trunk nod twice a stride, and a head that counter-rolls it.
  **Stagger the LAGS** — joints peaking on the same frame read as one welded block. `ogre.poseUpper` is the
  worked example.
- **FEET DO NOT SINK: level the ANKLE, never lift the BODY.** `legChain` measures the deepest sole corner
  against its `SolePatch` and rotates the ankle to clear. Also check the mesh: `addCube` takes a FULL size,
  `addCapsule`/`addBlob` take true RADII.
- **AN ATTACK IS A SEQUENCE OF KEY POSES CHASED BY SPRINGS, NEVER TWO CONSTANTS AND A LERP**
  (`anim.Key`/`keyAt`/`Spring`/`SpringBank`, `anim.Pose(P)`; Overgrowth's model — Rosen, GDC 2014). A move
  defined as A→B has nowhere to put a gather that loads, a hang that baits, a snap, a follow-through or a
  recoil, so it reads STIFF however the constants are tuned. No dial fixes that.
  - **THE POSE IS A TARGET, NOT THE OUTPUT.** A `Spring` output moves by velocity, so it cannot jump however
    far its target does — which makes every interrupt (stagger, parry, cut recovery, chain link) continuous
    for free, and retires hand-rolled cross-fades.
  - **THE CHAIN LAG IS THE BANK'S, NOT THE MOVE'S.** `SpringBank` pulls each channel a little less hard than
    the one before, so mass flows root→tip. The channel array's ORDER is load-bearing.
  - **SEAT THE SPRINGS AT SPAWN** (`SpringBank.seat`). A bank comes up at 0, and 0 is a real pose — arms
    straight down.
  - **`.hold` IS HOW A BAIT IS WRITTEN.** A delayed downswing whose pose creeps while it waits reads as the
    swing already starting.
- **THE CROSSING SIDESTEP IS GEOMETRY, NOT TUNED ANGLES.** One symmetric ±`STRAFE_ABD` sweep per leg, half a
  cycle apart. A planted foot is WORLD-FIXED (its offset sweeps back linear in distance). Ask for foot heights
  and solve for the knee. Cadence has one dial: speed / `STRAFE_CYCLE`.

### Animation art direction

- **IDLE** — upright, still, alive: a slow breathing bob only.
- **WALK** — unhurried, grounded, near-upright (~3° lean). RESTRAINED arms (never both forearms out front —
  the "zombie arms" fail). Low hip sway, clear heel→toe stride, slight toe-out.
- **RUN** — low and aggressive: deep lean over a crouched pelvis. Arms pumping at ~90°, not swept-back
  "naruto" arms. Real flight phase.
- **SPRINT** — the run dialled up: deeper, lower, longer, faster. Falling forward and catching it.
- **ROLL** — dive into a tuck, ONE somersault over ONE shoulder about a low ball centre (banked, uneven,
  drifting roll to roll — cosmetic only), then a spin-free rise. No float.
- Blends: idle↔walk by a `moving` ease; walk↔run↔sprint by ground speed. Pose discontinuities cross-fade
  ~0.09 s; stances never snap while mechanics stay instant.

## Adding a foe (`foe.zig`)

- **Satisfy the contract:** `pos`, an embedded `combat.Vitals` (`vit`), `hits`, `justDied`, and the accessors
  `alive/dying/staggered/airborne/bodyR/hurtRadius/centerWorld/lockPoint/topWorld/flashFrac` +
  `tryHit(foe.Blade)`.
- **Reuse the behaviour.** `tryHit` is TWO shared calls then what is yours: `foe.reached(self, blade) orelse
  return` (swept test, one-hit latch, anti-cheese rouse, the facing snap a `pierce` earns) then
  `foe.wounded(self, s, blade, .{ .light, .heavy })` (hit count, flash, shove — returning whether the BLOW was
  heavy, which is what blood and chips are sized off, never the REACTION). Only the shieldman has anything
  between them. Damage and the reaction live in `foe.strike` under `reached`.
- **The shared body points.** `foe.bodyPoint(pos, h, scale, lift)` for a height on the creature's own axis;
  `foe.markOn(bone, at)` for the reticle, which rides the POSE. `foe.stunCurve(t, heavy)` is the one reaction
  shape in the game. (The kobold keeps its own on purpose: its flinch decays from full rather than swelling.)
- **Build vitals with `combat.Vitals.initFoe`**, never `init` — that is the slow foe regen schedule.
- **`justDied` is a ONE-FRAME flag.** Reset at the TOP of `update`, set in `enterDeath`, apply the blade at the
  END. Applying it externally without the reset latches a nonstop rumble/shake.
- **EVERY BODY GOES OUT THE SAME WAY** (`foe.dissipate` + `foe.Dissolve`) — past its own `DEATH_DUR` the fall
  is over and it dissipates over `DISS_DUR` into gold motes rising and flakes falling. The two DURATIONS are
  per-creature, and so is the `Dissolve` (rate, spread, rise, flake colour); the SHAPE is not. It reads FIELDS
  only (`fade`/`scale`/`pos`/`parts`/`fxHead`/`fxAccum`/`fxRng`), which is what lets it live in `foe.zig`.
  **The SHADE is the one exemption, written at its own `.dead`:** nothing to shed, so it thins from frame one.
- **A BODY GOES BY GOING TRANSPARENT, NOT BY GETTING SMALL.** `foe.rigScale(scale, fade)` is the ONE dial and
  it is a tenth (`DEATH_SHRINK`). The vanish is an ALPHA: `drawGroup` hands the shader `1 − fade` through
  `Scene.beginFade` (depth-mask off while it draws). VIEW PASS ONLY — the depth pass has no fade uniform, and
  a body keeps its shadow while any of it is left.
- **A CORPSE IS NOT A COLLIDER.** `alive()` stays true through collapse and dissipation, so every collision
  site asks `foe.corporeal` (`alive() and !dying()`).
- **…BUT A BODY ON THE GROUND IS A CAPSULE, NOT THE RING AT ITS FEET** (`game.bodyOf`). Floored, the knight is
  5.15 m of armour lying behind his boots and the ring held 1.77 of it. A creature that can lie down answers
  `bodySeg` (`?[2]rl.Vector3`, off its own posed SKULL); everything else has no such state, and `pushOut` on a
  degenerate segment IS `pushOutCircle`.
- **Group + register.** Wrap instances in a `Group` exposing `anyDied`/`totalHits`/`aliveCount`; its `reset`
  and `draw` are ONE-LINE DELEGATES to `foe.resetGroup`/`foe.drawGroup`. The draw's `setFlash(0)` tail is what
  a fourth copy would forget.
- **CROSS-CUTTING STATE IS EMBEDDED BY THE CREATURE AND STAMPED BY THE GAME** — its eyes (`Leash`), a hold on
  its feet (`combat.Root`). The creature reads the field; it never reaches out for the state.
- **WHAT A CREATURE IS, AND HOW IT TRAVELS, ARE TWO AXES AND ONE TABLE** (`foe.Nature`, `foe.Gait`,
  `foe.traitsOf` — an exhaustive switch, so a new creature cannot be added unclassified). `Nature` is
  beast/demon/undead/humanoid/plant/construct; `Gait` is walking/waterfaring/flying/rooted and is what the
  water gate reads. **`Gait.flying` IS NOT `airborne()`** — that one is whether a body is off the ground THIS
  FRAME (a toad mid-hop) and it is what collision asks.
- **DENYING MOVEMENT IS A POST-STEP GATE, NOT A GUARD AT EACH MOVER** (`foe.grip` + `defer grip.hold`,
  `game.gateTerrain`) — taken once at the end of `update`, because a creature grows movements and a per-site
  list is a list to forget one from. It takes ONE thing, the feet: the state machine still runs, the kit still
  swings, blows still land. Y is left alone — `game.groundActor` owns it.
- **A JUMP IS THE ONE THING THE GRIP REFUSES OUTRIGHT** (`foe.canLeap`) — a leap does not TRAVEL, it leaves
  the earth. Denying only its distance leaves it hopping on the spot inside a fist of roots, so a jump skill is
  gated where the move is CHOSEN: the archer's backstep, the kobold's dash, the broodling's pounce, the
  greatsword's lunge, the toad's hop AND lunge. Ask it of the move's own `hop` (`warrior.decide` folds it into
  `ready`, so `classify` cannot promise a strike the pick then refuses), never of one move by name. Already
  airborne when the grip closes, it finishes its arc.
- **STEERING ROUND WHAT IS IN THE WAY IS `foe.Nav`, STAMPED BY THE GAME** (`game.markWay`/`markWays`). A
  creature owes a `nav` field and ONE method — `navWant(target)`, the point it is trying to walk at, or null.
  `markWays` is folded over `FOE_GROUPS` and keyed off `@hasField(M, "nav")`, so gaining steering is a field
  and a method and never an edit there — and a test pins field ⟺ method, because both halves fail SILENTLY.
  - **It is STEERING, not a route.** No graph, nothing remembered: a heading tested for the next couple of
    metres against `env.walkStep` and `env.resolveActor`, fan tried NEAREST-FIRST. It answers a body pressed
    into a wall; it does not claim more.
  - **The creature reads it in ONE place.** `Nav.aim` for one that walks where it is LOOKING (the ogre);
    `Nav.along` for one that steps on a committed vector with its eyes on him (kobold, shade, kiting archer).
    A hop is bent at the CHOOSE (`frog`, `shroom`), never mid-arc.
  - **ONLY THE TRAVEL STATE.** A swing, wind, lunge, leap and pounce are committed. **The attack hop is left
    straight on purpose** — that one is the attack.
  - **A FLYER IS NEVER STEERED** (`gateTerrain`'s `airborne` skip): the probe is the rule for FEET.
  - **It is asked about whoever the creature is actually FIGHTING** (`Threat.aim`), never about the hero.
- **A BODY THE NECROMANCER CAN USE IS A `raisable`/`reraise` PAIR AND A `heldOpen` FIELD** — nothing else, and
  no edit to `game.markVigil`/`applyRaises`, which key off `@hasDecl`. The field is named for what it does to
  the BODY, not for the creature doing it: one name for both had `foe.dissipate`'s probe matching the caster.
- **A multi-kind group answers for its own members** — `kind = null` in `FOE_GROUPS`, each member exposes
  `kind()`. A group with anything else on the field (sacs, acid) exposes `clear()`.
- **Anything the map can post is a `wf.FoeKind`, APPENDED never inserted** (editor unit brushes are pinned to
  that enum's order at comptime), plus `foeName`, a `unitTips` line, a `unitIcons` glyph and a `foeSwatch`.
  Several kinds of one creature go in as a CONTIGUOUS RUN, pinned at comptime.

### The Bone Knight (`knight.zig`) — first boss

Anor Londo Sentinel (docs/GIANT_KNIGHTS.md) on the ER knight brain (ELDEN_RING.md §7). 640 HP, five strokes
plus swat / hop / leap / shove / charge / fall. Memorization and attrition, never dice.

- **THE DOOR NEVER BREAKS; THE MAN BEHIND IT DOES.** No stamina pool on the door. A share of stance passes
  through (`TOWER_STANCE_PASS`, small) so frontal pressure earns a stagger, expensively. No poise ever — the
  door may not flinch him, and `POISE_MAX` is sized past what light spam reaches. Three PARRIES still break the
  stance.
- **EVERY DIMENSION OF THE DOOR IS DERIVED AND COMPTIME-ASSERTED, NEVER PICKED.** `TOWER_ARC` comes from
  `towerArc` — the widest chord against how far the face stands in front of his body axis, plus a named
  allowance for the swept kit; the chords are asserted past his pauldrons both sides, the bow is asserted real,
  and the height past a wall's proportion (>1.55× chord). Foot 0.24 m, top 4.75 m under a 5.11 m crown. Coverage
  is bought by building DOOR. **THE RAM IS NOT THE WHOLE FACE** (`SH_RAM_HALF`): bash and charge bill only the
  near-flat middle.
- **THE STANDOFF IS MEASURED OFF THE FIST, SO IT IS ONLY EVER THE LAST FEW CENTIMETRES** — the shoulder comes
  out of the reach and the elbow folds the forearm ACROSS his chest. The test brackets from BOTH sides and
  measures off the CUIRASS FACE, not his footprint. **EVERY POSE THAT LERPS OFF `GUARD_*` MOVES WITH IT** —
  `BASH_WIND_*` are those hauls re-based, and an absolute wind target silently loses its whole gather when the
  guard moves under it.
- **ANY ROTATION OF THE DOOR IS ABOUT ITS OWN CENTRE, NEVER ITS GRIP** (`SH_CENTRE_Y`). Gripped high like a
  pavise, a pitch about the hub sweeps four fifths of a four-metre plank through the knight.
- **THE ARM CANNOT CARRY IT — THE MOVE HAS TO** (`slamCarry`): the fist travels ~1 m and the door is 4.
- **A COMMITTED SWORD STROKE TAKES THE DOOR OFF HIS FRONT** (`swipeOpen`) — sweep, second sweep, overhead and
  the sword-side flick, open through the head of the recovery; thrust and bash keep the guard, and the
  shield-side flick does not pay because there the door IS the flick. **THE MECHANIC AND THE PICTURE ARE ONE
  CHANNEL** — `guardUp` and where the door actually is, test-pinned together.
- **HE TRACKS LIKE THE OGRE, AND THE WINDOW IS THE COMMIT — NOT THE FLANK** (owner: the ogre is harder, the
  knight is dull). `TURN_RATE` 3.20 rad/s, pinned into the ogre's class and under it (`ogre.TURN_RATE` 3.40,
  public for exactly this). He was at 0.68 — slower than the 0.80 a WALKING man carries — so a stroll in
  circles was the whole counter and most of the fight was him waiting. **YOU CANNOT OUT-CIRCLE HIM ON FOOT
  ANY MORE**: a sprint round him is 2.40. What he gives you instead is what the ogre gives you — the heavy
  commits. Quick rows hold you (`SWAT` 4.80, `THRUST` 4.40, `BASH` 4.00, against the ogre's swipe at 5.40);
  the heavies let go (`SWEEP`/`SWEEP2` 2.00, test-pinned under `TURN_RATE` and under half the swat's); the
  OVERHEAD lets go entirely at 0.
- **AND "DULL" IS A MEASUREMENT, NOT A FEELING** — 45 s of a hero walking a ring round him is 30 blows thrown,
  91% of the fight committed, and no lull longer than one earned reposition (a big recovery plus a step-turn).
  Test-pinned, because the failure it guards is the fight going quiet rather than anything going wrong.
- **AND HE SHUTS THE GAP RATHER THAN STANDING IN IT** — the HOP is the quickstep: 3.2 m in 0.54 s on a 2.6 s
  clock, taken on PRESENCE (a man circling him, or the thrust band with the thrust spent). At 1.6 m on a 7.5 s
  clock, gated on damage already banked, it fired about never and the thrust band was where you healed.
- **THE GATHER AIMS, THE COMMIT DOES NOT.** Every wind turns at his full `TURN_RATE` — it was 0.45 of it for
  all but the sweep's, which is why standing in front of him and strafing was free: the overhead brought 16° round
  across a 0.88 s gather. What still leaves the window is `Attack.track`, and the CHARGE's wind has always been
  allowed to aim past even that (1.4×) because what you dodge there is the travel.
- **HOW HARD A STROKE FOLLOWS YOU IS A PROPERTY OF THE STROKE** (`Attack.track`), not one global rate. HEAVY
  rows stay under `TURN_RATE` (test-pinned) — commitment has to cost him tracking or there is no window. The
  OVERHEAD tracks at ZERO and pays for it with `Attack.step` instead: **A STROKE THAT CANNOT FOLLOW YOU CARRIES
  HIM AT YOU** — the lunge is one column on the table and every stroke but the swat has one. **AND A SWING IS
  ONLY AS ACCURATE AS THE THING ON THE END IS WIDE**: `SWING_BEARING` may never exceed the kit's own subtended
  half-angle (the ram subtends 26°), and the drift a commit sheds may not by itself carry the kit off a
  squared-up man.
- **THE DOOR IS OAK, AND OAK IS NOT A WARD** — `TOWER_NEGATE` 0.90 against steel, `TOWER_NEGATE_ELEM` 0.60
  against anything thrown (`combat.guardChipSplit`). A rod is the way through his front, which is what pays for
  the front no longer being a safe place to stand. **AND IT LEAVES HIS FRONT FOR THE WHOLE COMBO**, not for each
  swing in turn: a link's own gather holds `swipeOpen` at 1 (`strung > 0`), and a link that keeps the guard by
  design — thrust, bash, a SHIELD swat — puts it straight back.
- **HE IS LEARNED, NOT ROLLED — AND THAT TEST IS THE DESIGN.** Attack choice is POSITIONALLY DETERMINISTIC: each
  band-and-side has an ORDERED PATTERN (`BOOTS_*`/`RANGE_*`) that `cursor` walks, a move on cooldown is SKIPPED
  rather than waited for, and `classify` is pure over one `Sit` so a test pins that the same place twice gives
  the same answer. The variety comes from the player's own feet.
- **INSIDE A BAND HE WEIGHS, HE DOES NOT WALK A LIST** (`weigh`) — every available entry SCORED, best taken,
  never a die. `W_ROTATION` is the biggest term and decays down the pattern from the cursor (ties to the nearer
  entry); `W_FIT`, `W_SQUARE`, `W_SIDE`, `W_PRESS`, `W_CIRCLE` and `W_LIT` are the rest. A bearing the arc
  cannot reach is a HARD gate, not a weight: that stroke is a guaranteed miss, not a worse choice.
- **A COMBO IS A FIXED ROUTE HE WALKS** (`routeFor`) — one route per opener, up to four links, cut short only by
  the player LEAVING. Nothing follows the OVERHEAD, so a route may only reach it as its LAST link (test-pinned).
  The four openers lead four pairwise-distinct places, and the cheapest (SWAT) opens the longest.
- **HE IS NOT MASHED OUT OF A STRING HE HAS STARTED** (`inString`) — mid-route the light flinch is refused; the
  OPENER is interruptible, and a STANCE BREAK always stops him.
- **A FLANK BLOW HE SHRUGS OFF IS ANSWERED** (`counterFlank`) — shoulders get a snap-and-swat, his spine gets
  the leap. It reads a blow that already landed on his own body and the bearing it came from (world state, never
  the player's buttons), is clocked, is refused out of anything committed, and is **refused outright if the blow
  staggered him**: an earned punish window is never taken back. Same rule for the door's own guard counter
  (`caught` → `riposteCd`).
- **NEITHER SHOULDER IS A FREE LAP.** The SHOVE (`shoving`, `shoveAcross`, `shoveDir`) hauls the door onto
  whichever flank you stand on, on the bash's own row and clocks, and buys it with his FRONT. SWORD side fires
  on presence; SHIELD side is bought with DAMAGE (`pressed`), or the door would collapse that whole flank onto
  one move.
- **LIGHT AND HEAVY ARE TELLABLE APART BEFORE THEY LAND** (`Weight`): the gather's FIRE says which — none on a
  light, a rim on a heavy, a column on a crusher, and it must be WIDER THAN THE DOOR to be seen at all. A test
  forbids tuning a move's damage up without its tell following.
- **THE MOVES THE BOARDS CANNOT ANSWER GET THE LONGEST TELLS.** Slam, charge and fall carry no parry window
  (`parryable`); their counter is DISTANCE, the sidestep and the roll. `FALL_WIND_DUR` is therefore bracketed
  from BELOW by every one of his own winds rather than by `foe.TELL_MIN`, and the charge's `windDur` 0.62 is a
  floor. **A RUN CLEARS THE SLAM'S DISC FROM THE MARK AND A WALK DELIBERATELY DOES NOT.**
- **A COMMITTED LINE IS COMMITTED AT THE LAUNCH.** The charge's wind aims (allowed 1.4× his turn) and the travel
  steers not at all, test-pinned frame by frame; `brakeDist` integrates to `speed × brakeDur / 2`. Leap, hop and
  charge are all gated at the CHOOSE by `foe.canLeap`.
- **THE DISC IS DRAWN BEFORE IT IS BILLED** (`slamRingTell`) — the blow's own circle walked during the WIND off
  the same `slamMark`/`SLAM.r` the mechanic uses, in EMBER because tan on tan is unreadable.
- **STOOD DEAD BEHIND HIM HE FALLS ON YOU.** `fallwind` is the one move that steers AWAY from the hero — the
  spine coming round IS the tell. The crush is a STRIP down the line behind him, DERIVED off the rig, carrying
  the biggest POISE and STANCE in the game (`game.BLOW_HEAVIEST` is a `@max` over it and the ogre's slam) at
  only 34 damage, because it is the hardest to read. **THE SAFE POCKET IS HIS QUARTER, NOT HIS BACK**:
  `FALL_SECTOR` 70° is strictly outside `TOWER_ARC`, the gap between them test-pinned over 20° wide, and the
  widening is paid for with the AIM (`FALL_AIM` 0.62 rad/s, still under `TURN_RATE`).
- **THE AFTERMATH IS THE REWARD** — flat for `DOWN_DUR`, over onto his front, up off the shield, door down for
  all of it, cooldown outlasting the rise. **AND A BODY ALREADY ON THE GROUND CANNOT BE FLINCHED UPRIGHT**
  (`floored`): damage, flash, chips and stance still land, only the state change is refused. Death goes through,
  and `enterDeath` records the topple the body was at (`deathFrom`).
- **ONE CHANNEL SAYS WHERE HIS BODY IS** (`toppleAmt`, `rollAmt`) — 0 standing, 1 flat, NEGATIVE forward, which
  is the only way he dies. Topple rotates the ROOT about the ground between his feet; roll is `ry(180)` inside
  the rig, and `turnAbout` exploits `Ry(180)·Rx(θ) == Rx(−θ)·Ry(180)` so the swap is invisible on the frame it
  happens. **SO EVERY WORLD POINT COMES OFF A POSED BONE**: `centerWorld` the pelvis, `lockPoint` the chest,
  `topWorld` the helm. A height off his feet would hang in the air over a body on the ground.
- **AN EFFECT'S PHASE IS ITS OWN DECAY, NOT A CLOCK BESIDE IT** — the landing ring runs off `thud`, not `self.t`,
  which resets on every state change.
- **HE FALLS, HE IS NOT LOWERED** (`deathTopple`) — quadratic to `DEATH_LAND` (0.62 × `DEATH_DUR`), then
  OVERSHOOTS and settles (`DEATH_BOUNCE` 5.5°). The body arriving is an EVENT: dust, `QUAKE_BRAKE`, and
  `audio.mkKnightDie` on that instant. **A FELLED STATUE DOES NOT CURL** — flat, both legs straight, pinned at
  the ankles (1.11 m against a 1.51 m knee).
- **THE ANIMATION CONTRACT IS FIVE PHASES** (ELDEN_RING.md §7): opening pose → signal → a strike of almost no
  time → **held End Pose** → return. Every move is a KEY LIST per phase (`SWEEP_KEYS` &c) and the End Pose is
  gained by writing no further key — the track clamps. Tests pin the seams (`wind[1.0] == strike[0.0]`) and that
  every stroke HAS a shape. The outward lag is the spring bank's, never hand-derived curves.
- **HE TURNS ON HIS FEET** — `legChain` is driven by GROUND COVERED and a pivot covers none, so the arc each foot
  sweeps about his stance half-width is handed to the gait as lateral distance. `planted` holds them down through
  a committed stroke: **a giant swings by planting.**
- **THE GROUND HE MOVES IS FELT ON EVERY LANDING** (`quake`/`QUAKE_*`, a one-frame magnitude like `justDied`,
  wired through `Vigil.quakeAmt`), sized to the mass that arrived — the overhead ends in the EARTH, so it is a
  landing and not a swing.
- **PHASE TWO FOULS THE GROUND.** Once lit, what shows FIRE and STOPS leaves a `knight.Gas` cloud, decided by
  the `Weight` rule and laid at the IMPACT FRAME so a stroke that MISSED still denies that ground. FALL and
  CHARGE are excluded — each is already position-denial, and fouling where it ends taxes the answer the move
  demands. **THE LIT CHARGE FOULS THE LINE INSTEAD**: `chaosTrail` drops a cloud every `CHAOS_TRAIL_EVERY` of
  GROUND COVERED (never on a clock, or at 12.4 m/s it lays twenty a second), spaced wider than a trail cloud's
  own reach so the lane has crossings in it. `GAS_CAP` 12. **The cloud is the GROUP's, not the knight's** — it
  must keep burning after the body that laid it has fallen — and it carries NO poise and NO stance.
- **THE BOSS BAR** (`hud.bossBar`): `game.zig` owns when it shows (`Vigil.boss`) and SUPPRESSES that body's
  floating bar — one number may not be read in two places. `bossK`/`bossFrac` assigned in `init`.
- **Art and audio.** `PLATE` = `.plain`, `BRIGHT` = `.steel`: `Mat.steel`'s specular is catastrophic on a face
  the size of a door, so `.steel` is for what is SMALL AND PROUD. The iron is BLUE-BLACK because everything
  outdoors here is warm; the shield's bands are ONE substance with a few points of value on them; his rust is
  his own, solved to ~120. Big smooth sealed masses, few of them. The sword's carry is test-pinned off the POSED
  bone, and **the tilt is MEASURED by bisecting on the carry test's printout, never reasoned from the matrix
  convention.** The blade's wake spans the outer HALF and lives well INSIDE the strike. Dust on this ground is
  tan on tan, so it reads by COUNT, billow and LOFT, and both emitters are pinned by particle-count probes in
  the soak test. **Judge a stroke on a strip** (`shots.knightStrokeStrips`) and spend the frames where the motion
  is — the sweep is 1.10 s of wind to 0.38 s of strike. Ten `knight_*` voices, sharing only
  `swing_light`/`swing_heavy`: **iron over bone, nothing alive inside it** — a `ring` of struck plate over dry
  `grit`, checkable on zero-crossing rate, with every voice floored at 90 crossings/s so nothing is spent under
  what this gets played on.

#### His door (`props.Info.ward`, `env.ward*`, `game.markWards`)

- **A FOG GATE IS A WALL UNTIL HE ASKS TO PASS IT.** The ONE crossing allowed is `enterGate`'s walk, through the
  ward that walk is on (`env.wardRefusing`), refused on the SEGMENT rather than left to the push-out — a roll is
  3.5 m in one step and the sheet is 0.8 m thick. A SPENT gate never answers (`eachSolid` retires it at
  `wardLife` 0).
- **THE LATCH AND THE DOOR ARE DELIBERATELY APART.** The latch is his own step crossing the sheet
  (`markWardStep`); the door is only SHUT while the creature `Op.boss` names is still standing, so killing it is
  what lets you back out. A gate may not shut on the man in it (`wardClear`). It is a wall to every FOE and
  every LOOK regardless.
- **THE SEAL IS OWED AN ANSWER** (`fog_felled`). DARK is a REGISTER and FRIGHTENING is an INTERVAL: keep the
  seal's root (A1, 55 Hz) and its subterranean band, swap the TRITONE for the perfect FIFTH with the major third
  landing last. One shot, off the first frame of `wardLife` leaving 1.

### The delver (`delver.zig`) — goes UNDER the world

- **SUBMERGED IT CANNOT BE STRUCK, AND THAT IS GEOMETRY.** `depth` rides as a NEGATIVE lift through
  `foe.bodyPoint`, so hurt sphere, bar and reticle all sink and the swept test refuses it on its own. A
  comptime assert pins the clearance.
- **`airborne()` IS TRUE WHILE IT IS DOWN** — it is UNDER the world's traffic: no terrain riser rule, no
  shoulder, no steering, no jaws from the wolf, no spirit. NOT exempt from `env.resolveActor`.
- **THE DIVE IS A LEAP AND THE ROOTS REFUSE IT** (`foe.canLeap`) — gated at the choose AND re-asked at the
  launch, since a root closing during the wind arrives after the decision.
- **IT STAYS DOWN** (`UNDER_MIN` 2.6 s) whatever it finds, and never past `UNDER_MAX`.
- **TWO WAYS OUT.** Under him it BURSTS — a ring round the hole, counter is your feet. In front of him it
  PLOUGHS: the ridge stops turning, STRETCHES down its existing heading (`moundLong`, not a bigger `moundR`)
  and drives a furrow at `PLOUGH_SPEED`, the only thing it owns that catches a sprint. Patience exit is the
  plough. Lighter than the burst on all three counts, pinned by comptime assert — `game.zig` splits the felt
  beat on `hit.stance >= BURST_HIT.stance`.
- **THE CLAW COMES BACK** (`rake`) — FASTER than the opener, still clears `foe.TELL_MIN`, parryable on its own
  window, ROLLED not guaranteed, and only thrown while he is still standing in it.
- **NO LOCK-ON WHILE IT IS UNDER.** `hidden()` is the Rooted's predicate, found by `@hasDecl` in
  `game.disguised`. It is `deep()` and not a clock of its own — the same thing `Model.draw` hides the body
  behind.
- **THE SPOT IS COMMITTED THE FRAME THE MOUND STOPS.** A RUN or ROLL clears the ring, a WALK deliberately does
  not — both bracketed by comptime asserts against the hero's numbers.
- **THE TELL IS THE LONGEST THING IT DOES** (`SURGE_DUR` 1.15 s), on top of a visible mound.
- **THE BURST IS NOT PARRYABLE AND THE CLAW IS.** The blow is a RADIUS, not a swept limb, and its `from` is the
  hole — so stood dead on it there is no bearing and boards cannot answer (the zero-`fromDir` rule).
- **THE THIRD CHANNEL OF THE TELL IS THE PAD** (`Warrens.anySurged` → `game.SHAKE_SURGE` + rumble). This is the
  one move that arrives from a direction the lens cannot be turned toward.
- **THE MOUND IS NOT PART OF THE BODY** — matrix built in WORLD space at the surface. SIZED TO THE RING it
  announces, and it comes apart across the rise.
- **PARTICLE COLOURS ARE LITERAL SCREEN VALUES WHERE MESH COLOURS ARE ALBEDOS** (`CLOD` against `SOIL`).
- **A ROOT PITCH ROTATES ABOUT THE POINT ON THE GROUND**, so the root is lifted by exactly what the tip sinks,
  the lift fading out with the depth.
- **THE HIDE IS COOL WHERE THE SOIL IS WARM**, solved off a sampled render.
- **IT REARS TO STRIKE.** Shoulders sit at 0.40 m; held flat the rake topped out under his knee while
  `weaponReaches` still reported a hit.

### The necromancer (`necro.zig`)

Never touches you; priority target on any field. 78 HP, 12 poise, 320 souls.

- **THE CORPSE IS THE MECHANIC.** A skeleton is `DEATH_DUR + DISS_DUR` = 2.05 s from killing blow to last
  mote, which will not hold a raise with a readable tell inside it. So a body inside `RAISE_R` of a living
  necromancer **STOPS DISSIPATING** (`heldOpen`, stamped by `game.markVigil`, read by `foe.dissipate` through
  an `@hasField` opt-in). The held corpse is the FIRST tell and arrives before the cast.
- **IT IS A PLACE, NOT A LIST.** Flags cleared and re-earned each frame off where bodies actually lie. **Two
  cannot claim one body** — walked in order, an already-stamped corpse skipped.
- **A BODY MAY BE RAISED ONCE** (`wasRaised`) at `RAISE_HP_FRAC`, full poise and stance, into a light stun so
  it cannot swing out of the ground. **The shield does not come back** (`shieldGone`).
- **THE CREATURE ONLY REPORTS IT** (`raised`, one-frame, and `raiseAt`) — `game.applyRaises` does the raising.
  `foe.rekindle` is the shared re-arm and reads FIELDS ONLY; the STATE it comes up in is each creature's own.
- **THE RAISE IS THE LONGEST TELL IN THE GAME** (`RAISE_WIND` 1.90 s), PLANTED for every frame. It turns to the
  BODY, not to him. The spot is committed the frame the gather starts.
- **THE ICE RUNE RING IS THE OTHER HALF** — committed to the ground where he stood, and it OUTLIVES THE
  CASTER. Not parryable; its blow carries the RING as `hitFrom`, so stood on the mark there is no bearing.
  **`FROST_FUSE` is SOLVED**: long enough that a WALK clears the rim from dead centre.
- **THE FUSE BURNS ROUND THE RING RATHER THAN FILLING IT** — runes take one by one round the rim, the last one
  lighting IS the blow. **Built from `drawSphereEx` and nothing else**: `drawLine3D` is one pixel however close,
  and a `drawTriangleStrip3D` annulus came back invisible.
- **THE MARK TAKES THE GROUND AT THE MARK — THE TARGET'S OWN `pos.y`**, never the caster's, or a ring twelve
  metres away is depth-culled under the turf.
- **TALL AND SKINNY IS TWO DIALS AND THE RATIO IS THE CLAIM** — stature through `SCALE`, and `restHumanoid`'s
  `hx`/`sx` narrowed. Either alone is satisfiable by the wrong creature. A test measures stature over shoulder
  SPAN against the archer beside it.
- **THE DRAGGING HEM IS NOT A BONE** — it rides the ROOT through a lag matrix, and it is a SPRING not an ease:
  the lean opposes the travel, OVERSHOOTS and settles (test-pinned, since an ease cannot overshoot). **Skirt
  panels are thin walls at the RIM**: `addBox` takes HALF-axes, so a radial extent of `r/2` centred at `r/2`
  spans axis to rim and every panel comes out a solid pie slice.
- **THE STAFF ARM MUST BE THE RIGHT ONE.** `heromod.PARENT[HELD]` is `WRR`; authored on the left, the pole's
  matrix was built against an unwritten `wx[WRR]` — undefined memory, staff transformed to the world origin.
  `poseUpper` poses that arm LAST, with the staff after its own wrist.
- **`staffTilt` IS 180-IS-PLUMB** (the warriors' `wpnTilt` convention). **The fit bills the ARM but not the
  TRUNK**, so a pose that arches the spine pays at its own constant (`RAISE_LEAN` 22°). All three poses are
  MEASURED and bracketed — carry 16° ferrule down, raise 9° planted, frost 31° ferrule LIFTED.
- **THE FROST NEEDS TWO PALETTES FOR ONE SUBSTANCE** — `RIME_ALB` goes into meshes (×1.72 → gamma); `RIME` is
  drawn unlit and is a literal screen value.
- **THE ROBE'S HUE HAS TO BE LAID ON THICK** — the warm key multiplies through, so blue must run at better than
  twice red in the ALBEDO to survive to screen.
- **NO VOICE OF ITS OWN YET** — borrows `shade_reach`/`shade_gather`/`shade_touch`, `wand_charge`/`wand_cast`,
  `bone_hurt`/`bone_die`.

### The leechfly (`leechfly.zig`) — the first flyer

`pos.y` is the ground under it and `hover` is what it flies above that by; every world point (`centerWorld`,
`lockPoint`, `topWorld`, hurt sphere) is measured off `pos.y + hover`.

- **IT ZOOMS OUT OF SWORD REACH.** Threatened, it climbs to `HOVER_HIGH` (4.6 m) in a third of a second, works
  round behind him, and dives back. The blade cannot reach that; an arrow and a bolt can. That trade IS the
  fight.
- **THE CLIMB IS A LEAP AND THE ROOTS REFUSE IT** (`wantsClimb` → `foe.canLeap`).
- **ALWAYS `airborne()`** — terrain gate never applies, nothing on the ground shoulders it. NOT exempt from
  `env.resolveActor`.
- **THE FEED IS A BLOW AND THEN A HOLD, DOWN DIFFERENT CHANNELS.** The beak is a real `foe.Blow` — blockable,
  carries where it came from. The swallow is a DRIP (`game.leechSip` → `hero.burn`), billed per SECOND, scaled
  by `dt`. A shield answers the first, only the ROLL the second: `holds()` is re-asked every frame and tests
  height as well as bearing.
- **IT HEALS OFF WHAT IT TAKES** (`LEECH_SHARE`, some not all). The belly (`gorge`) fills and STAYS full.
- **THE EYES COME ALIGHT WHILE IT DRINKS** — drawn in `drawFx` as unlit spheres over the opaque pass, because
  vertex alpha is a FIXED emissive channel and cannot brighten.
- **THE WHINE IS A RETRIGGER, NOT A LOOP** (`WHINE_EVERY`) — raylib cannot loop a synthesized take. Cut a hair
  LONGER than its own period so takes overlap; gapped, it chatters at 4 Hz and reads as a helicopter.
- **A SWATTED FLY DROPS.** Stun states pull `hoverTo` down. Death is the hover running out before
  `foe.dissipate` takes it.

### The florid ravager (`ravager.zig`) — the flower IS the window

A hound's body on a two-metre woody stalk, with a flower where the head should be. `wolf.zig`'s 27 bones plus
FOUR appended above them, so `wolf.legs` still takes `wx[0..wolf.N]` as its own array and no bone it solves has
moved. The muzzle and the two ears are re-let as petals rather than left nodding on a flower.

- **IT ONLY BLOOMS WHEN IT IS WARMING UP TO ATTACK, OR WHEN A HEAVY STUN BLOWS IT OPEN** (owner). One scalar,
  `openAmt`, read off the leap's own clock or the stun's and nowhere else — never off distance. A bloom that
  opened on APPROACH was a tell for standing still, and it made the flower ambient rather than an event.
- **AND OPEN, IT TAKES MORE DAMAGE** (`frailty`, `BLOOM_FRAIL`) — 1.9x wide, on the BLADE in `tryHit` so the
  cull, the threat and the shield all see the blow that landed. **DAMAGE ONLY**: `poise` and `stance` ride
  through untouched, because `POISE_MAX` is solved to sit between his light (10) and his heavy (22) and a
  multiplier there would quietly put a light poke through it. The window is a punish, not a second stagger.
- **THE SWIPE CARRIES NO WINDOW** — it is the flank answer, its tell is the SHOULDER DROPPING, and every bloom
  clock gates on `.bite` or the stun. Two moves, two grounds, one of them punishable.
- **WIDE BEFORE IT LEAVES THE EARTH.** `LAUNCH_T` is 0.55 of the wind, so the burst has to finish inside
  0.209 s — a comptime assert, and it is what caught an `OPEN_BY` of 0.70 reading as a tell it was not.
- **SEVEN QUILLS, HAND-LAID, AND THE UNEVENNESS IS BOUNDED BOTH WAYS.** Gaps of 34 to 58 degrees against an even
  ring's 51: pushed at the bottom because `k/7 * 360` reads as a gear, capped at the top because a 76-degree gap
  came back as a bald sector in the open corolla.
- **THE FOLD BUYS RADIUS UP TO 73 DEGREES AND SELLS IT AFTER.** A tip's distance off the bloom's axis goes as
  `(BOW+RECURVE)*cos f + sin f`, so `PETAL_WIDE` dialled UP past the peak makes the flower NARROWER — at 128 the
  corolla measured 0.76 m across against 1.72 m at 95. Same trap on the SWEEP, which is tangential in the
  petal's own frame but still `hypot` against the axis: 34 degrees of it put the SHUT bud at 0.97 m across.
- **A SECOND TIER FOR NO BONES.** Each petal bone carries a short broad TONGUE as well as its quill, pitched
  `INNER_TILT` further in by a rotation baked into the MESH. Shut they cross the axis and seal the bud, which is
  what keeps the throat's light off; open they cup it. A constant tilt is an OFFSET, so its length is solved
  against `BLOOM_RIM` or the tongues come out the far side.
- **THE STALK TELESCOPES AND THE HEAD'S OWN COLLAR COVERS THE SLIDE.** The reach is a translate on `HEAD` along
  the neck's axis; the head's mesh hangs a 0.47 m sheath INSIDE the stalk's bore, thinner than the bore, so no
  frame of a 0.35 m stretch shows a gap.
- **THE STALK REARS OFF ITS OWN CLOCK, NOT OFF THE BLOOM** (`rearAmt`) — coupled, a heavy stun reared the neck
  it is supposed to fold.
- **A CORPSE WILTS FROM WHATEVER THE BLOW CAUGHT IT WEARING** (`deathOpen`). Snapping shut is a pop and ramping
  from wide is the same pop the other way.

## Combat

**The two sides are tuned SEPARATELY.** A stagger you inflict is a punish window you must be able to walk
into; a stagger you suffer is time taken off the player. Hence `FOE_*_STUN_DUR` well past the hero's and
`FOE_REGEN_*` far slower.

**NOBODY IS POISE-DAMAGED WHILE ALREADY REELING, EITHER SIDE.** While a stun runs, incoming poise is dropped;
when it ends, poise goes back to FULL, both tiers. HP and direct STANCE damage still land. `combat.Vitals`
owns the clock (`stunLeft`, armed by `beginStun`), and it ticks BEFORE the regen gate or a foe's `regenDelay`
outlasts the window and the immunity never lifts. A GUARD BREAK is the one door `hit()` misses —
`hero.enterStun` arms it.

**A DRIP IS NOT A BLOW.** Anything that HOLDS bills damage every frame (`Vitals.drip`), and a blow's side
effects cannot be billed at that rate. TWO clocks: `sinceHit` gates the poise/stance refill and only a blow
moves it; `sinceHurt` is what the floating bar reads and anything taking HP moves it. **A drip that KILLS is
reported, not acted on** — only the creature knows how to die.

**A BLOW MAY TAKE THE BLUE BAR** (`combat.Hit.fp`) — the shade's touch, the only thing that does. NOT part of
`Hit.raw()`: what a shield's stamina bill measures is the WEIGHT of the thing that hit you. `hero.takeHit` is
the one place it is spent (`Focus.drain` FLOORS, where `Focus.spend` refuses), and the guard chips it by the
same fraction it chips damage.

**A RANGE GATE IS MEASURED FROM THE TARGET'S HIDE, NEVER ITS CENTRE** (`knight.triggerR` adds `HERO_REACH`;
`wolf.triggerR` adds the quarry's `bodyR`). `env.resolveActor` holds an attacker `bodyR + its own` out, so a
flat centre-to-centre range is unsatisfiable on anything broad. Derived off the hide the margin is the same
1.5 m on every creature. **HEIGHT IS A SEPARATE QUESTION FROM REACH, so it needs its own test** — the bash's
swept segment spanned only the middle 78% of the door and bottomed at 1.29 m against a hero whose chest is at
1.12 m. A "below his crown" assert passes on a blow that only touches hair; ask for CHEST height. Both tests
print their measurements.

**A TIMED STATUS REFRESHES, IT DOES NOT STACK** (`Root.grab`, `Regen.start`).

**A THROWN SORCERY REACHES ONE BODY; A HELD ONE REACHES WHAT IS IN FRONT OF HIM.** A sorcery thrown into a
warband picks ONE victim — the locked foe, else nearest to the mark (`game.rootVictim`) — so its reach is a
search, never a blast, and the FX is sized to the BODY (`combat.ROOT_GRIP_R`), not to the reach.

**THE RIME BREATH IS THE ONE EXCEPTION, WHICH IS WHY IT IS A CONE AND NOT A BLAST.** It is not thrown AT
anything: a direction held in front of himself for `RIME_DUR`, answered by not standing there. Priced off the
single-target ladder — dearer than the roots (15 fp against 12) and the worst of the three at killing anybody
(`spellDamage(.rime)` under the roots' whole grip). A comptime assert pins both.

**AN EFFECT'S CLOCK IS DERIVED FROM THE MECHANIC'S, NEVER PARALLEL TO IT.** And when the effect STAGGERS its
parts, its container outlives the mechanic by that stagger.

**FEEDBACK ON A CREATURE IS SIZED BETWEEN TWO FAILURES.** Under, scenery round the ankles; over, it hides the
creature it points at. Judge against the CREATURE, never the hero who caused it.

**A FLOATING BAR TIMES OUT; THE FIXED ONE DOES NOT.** It goes with the RETICLE, not `g.lock`, so a suspended
lock takes the bar down with the dot.

**AND IT MAY NOT CLIMB OUT OF THE FRAME** (`hud.FOE_CEIL`). Bars hang off `topWorld`, right at every distance
you can see the whole creature at and wrong the moment you close on a TALL one. So the bar is OVERHEAD unless
that would put it above three quarters of the screen — one `max` against a screen-space ceiling. ONE rule for
every creature.

**THE RETICLE RIDES THE BODY, NOT A HEIGHT OFF THE FEET** (`foe.markOn`, each creature's `lockPoint`). Each
creature names the PART its mark rides and a point in that bone's frame: skull for the three humanoids, brow
for the toad, cephalothorax for the spiders, cowl for a shade, CHEST for the ogre (crown 4.4 m up). The egg sac
is the one exception — one membrane on the ground has no part that moves on its own. A bone matrix already
carries the rig's scale, facing and `pos`, and every `spawn` poses before it returns. **A test pins the whole
rule at once** (`game.zig`, "THE MARK RIDES THE BODY") and it measures the mark's swing OFF THE CREATURE'S OWN
AXIS, not its height — a fixed mark still rises and falls on a hop, and nothing on the axis can leave it.

**A HEAD CAN GO BEHIND THE EYE.** Stood at a giant's feet its crown is above AND behind the camera, which
`projectToScreen` refuses. The fallback anchor is the CHEST (`centerWorld`), and the ceiling then puts the bar
where the head would have been.

### Stamina

- **AN EMPTY BAR LOCKS OUT roll / attack / sprint** (`STAM_LOCKOUT`). Not time theft: the consequence of a
  choice made a second earlier, readable off a bar.
- **WALKING IS NEVER GATED.** Running dry caps `mv.speed` to `RUN_SPEED`, denied at the SOURCE so
  `sprintingMove` stays the one definition of a sprint.
- **RUN IT OUT AND YOU ARE WINDED** (`STAM_WIND_CLEAR` 0.5): sprint stays denied until the bar is back to HALF.
  A LATCH, not a `cur == 0` test, latched by `settleWind` from every path that moves `cur`. Sprint only. The
  bar draws the mark (`Stamina.windedTo`).
- **YOU MAY ACT ON ANY STAMINA ABOVE ZERO** — `canAct()` is `cur > 0`, NOT `cur >= cost`. That asymmetry is
  the PANIC ROLL.
- **A COMMITTED ACTION IS NEVER CUT SHORT.** `spend` floors at 0; nothing is refunded or aborted.
- **THE REFILL PAUSES** while attacking, rolling or sprinting, then waits `STAM_DELAY`.
- **A REFUSED ACTION IS SHOWN** (`hero.stamRefused` → red ring). Under zero-input-lag, silence is
  indistinguishable from a dropped input. Feedback only.

### Guarding — the plain DS1 block, not ER's

- **IT IS A HELD STATE, NOT A COMMITTED ACTION.** `hero.setGuard(want)` is called every frame with the
  button's level and re-derives from scratch (`canGuard`). Call it AFTER `sprinting`.
- **THE SHIELD IS A DIRECTION** (`combat.GUARD_ARC`, 65° either side), not a bubble — which is why guarding
  cannot answer a warband the way rolling can. A blow with a zero `fromDir` is never blocked, which is what
  lets `--shot` force reactions with synthetic hits.
- **SO A BLOW CARRIES WHERE IT CAME FROM.** Every group's update returns `?foe.Blow` (hit + attacker pos), not
  a bare `?combat.Hit`. An arrow's direction comes off its own velocity reversed.
- **IT COSTS STAMINA, NOT POISE** — `GUARD_STAM_FLAT + GUARD_STAM_PER_DMG × dmg`, refill paused while up.
- **CHIP GETS THROUGH AND CHIP CAN KILL** (`GUARD_NEGATE` 0.85), routed through `Vitals.hit`. Stability is poor
  by design: kobold teeth ~15 of 105, the ogre's club ~45.
- **EMPTY THE BAR UNDER A BLOW AND THE GUARD BREAKS** — heavy stagger, and the shield cannot come back up
  until the pool refills. The danger is the NEXT hit.
- **`takeHit` RETURNS WHAT BECAME OF THE BLOW** (`HitOutcome`) and `game.heroTakes` is the ONE place that turns
  it into a felt beat.
- **HE CAN WALK A FIGHT DOWN BEHIND IT** — `hero.GUARD_SPEED` 0.75 of the walk, capped against the walk, never
  zeroed; denied at the SOURCE like the sprint.
- **THE STANCE LAGS, THE BLOCK NEVER DOES.** `guarding` is live on the button; `guardB` is a visual blend
  (~0.1 s). Nothing mechanical may read `guardB`.
- **THE MAN MOVES, THE SHIELD HOLDS.** Recoil goes into the BODY (sink, step back, camera, pad), only a little
  into the arm.
- **The shield is not a bone** — it rides the left wrist through `hero.shieldFit`, DERIVED from the stance
  angles (their inverse), or the first retune swings it off its own arm.

### Parrying — L2, the shield's own skill

- **L2 IS THE LEFT-HAND ARMAMENT'S SKILL SLOT**, routed by that hand exactly as L1 is: a raised bow AIMS on a
  held level, boards PARRY on a pressed edge. It asks NOTHING about whether the guard is up.
- **ON THE MOUSE THE TWO HALVES OF L2 PART COMPANY** (`PARRY_KEY`). RMB is the guard's held level, and
  Shift+RMB would fire a parry every time a sprinting player pressed RMB. So the edge takes its own key.
- **THE WINDOW AND THE ANIMATION ARE TWO CLOCKS** (`parryLive` vs `PARRY_DUR`). The catch is open ~0.16 s; the
  shove plays a quarter second after it shuts, and `canGuard` refuses the whole time. That tail IS the price.
- **IT IS SLOW OFF THE MARK** (`PARRY_OPEN` 0.10 of 0.52). Widening `foe.PARRY_LEAD` makes catches easier;
  this makes STARTING one a commitment. Separate dials on purpose.
- **THE ATTACK ALWAYS DIES; THE HEAVY STUN IS EARNED.** `combat.PARRY_HIT` is STANCE and nothing else — no
  damage, no poise, so a catch can never resolve as a flinch: it breaks the stance or it does not.
- **THE CREATURE READS THE SHIELD, IT NEVER REACHES FOR IT** (`foe.Parry`, stamped by `game.markParry`). Each
  MOVE answers for its own frames and reach (`ogre.parryable`). **MOST OF THE FIELD CARRIES WINDOWS NOW** —
  fifteen creatures, every committed limb from the toad's leap to the skitterer's slam, each declared at its
  own `parryable`. Adding one is a `parry` field, a `toImpact`, a `parryable` and its group's
  `setParry`/`anyParried`: **`game.markParry`/`anyParried` are folded over `FOE_GROUPS` and keyed off
  `@hasDecl`**. `parryBeat` fires ONCE a frame for the whole field.
- **WHAT IS *NOT* PARRYABLE IS A DECISION, WRITTEN AT EACH `toImpact`** (or at the impact site of a move with
  none). A projectile is not a blow (spit, clump, every arrow). The toad's HOP carries no blow and its CHOMP is
  out on purpose. A BROODLING is out. **THE LEECHFLY IS OUT BY DESIGN**: its counters are the ROLL and the
  ranged kit, and a window on the stab would make the boards the answer to a flyer. A GROUND DISC has no
  bearing to catch (the delver's burst, the golem's smash and slam, the sporeling's splat); a POURED ELEMENT
  has no swung mass (the priest's breath, the mage's flick) — each says so where it lands. **HYPER ARMOUR IS
  NO DEFENCE** (`warrior.takeParry`) — it refuses poise off the blade, and a parry deals neither damage nor
  poise, so the greatsword's uninterruptible slam is exactly the move the boards can still stop.
- **A WINDOW IS `foe.PARRY_LEAD` SECONDS BACK FROM THE IMPACT FRAME** — one number, in seconds, for EVERY
  creature and move, and it IS the difficulty. **It is 0.18**, and every creature's tests BRACKET it from
  above: a window may never be more than a fraction of the tell in front of it. Written as fractions of each
  state's own clock instead, the total was emergent and unreadable.
- **SO IT SHUTS AT THE IMPACT FRAME BY CONSTRUCTION** (`toImpact` counts across the state boundary).
- **IT IS A SWIPE, AND THE SWIPE COMES FROM THE WAIST** (`parrySweep` — coil, whip across, settle). A shoulder
  yaw turns the boards' FACE with it, because `shieldFit` is the inverse of that yaw; the TRUNK turns arm and
  boards together. `PARRY_ARM_LEAD` adds a few degrees so the boards outrun the chest.
- **THE SHOVE MAY NOT BREAK THE FOLD.** `shieldFit` is also the inverse of shoulder-flex + elbow, so the
  shoulder takes `PARRY_PUNCH` and the elbow gives back exactly as much: what travels is the HAND.
- **THE OGRE SAYS WHEN HE COMMITS.** The ROAR at the top of a wind says a swing is COMING; the commit tell says
  NOW, once, on the wind → swing boundary, in all three channels: `ogre_heave`, `plantBurst` off BOTH FEET, and
  the shoulders driving over in the pose.
- **JUDGE IT FROM ABOVE.** A lateral arc foreshortens to nothing head-on, so the harness shoots the coil, the
  crossing and the follow-through straight down (`20o`/`20p`/`20q`).
- **A CATCH IS A BLOCK'S RECOIL PLUS SPARKS** — `noteParry` stamps `blockT`, the same channel. Sparks separate
  on HUE (hot amber on pale tan) and their FAN outruns their forward throw.
- **THE SWIPE ITSELF THROWS A GLINT, CAUGHT OR NOT** (`parryGlint`), ONCE on the whip's peak frame. **LAID
  ALONG THE ARC, NOT THROWN FROM A POINT** (`PARRY_GLINT_SPAN`), so it is a STREAK from the first frame. Count
  buys brightness; a TIGHT fan and SHORT lives keep it a glint. Always less than a catch, never a different
  colour — what separates the two is size.

### The jump — A/Cross

Traversal, not a technique (`hud.BTN_JUMP`, keyboard `V` — A is strafe-left, so the letter cannot be mirrored).
It costs NO STAMINA. No jump attack and no fall damage yet.

- **`pos.y` IS STILL THE GROUND UNDER HIM** — `game.groundActor` its only writer, `hero.lift` what he is flying
  above it by. The height integrated is `airY` (WORLD height of his feet) and `lift` is DERIVED off it
  (`airY − pos.y`) every frame — which is what makes running off a ledge work. **`lift` is ZERO unless he is
  airborne**, so a teleport can never strand him standing on nothing.
- **TWO NUMBERS ARE THE DECISION AND THE OTHER TWO ARE SOLVED** — `JUMP_APEX` (1.0 m) and `JUMP_AIR` (0.72 s);
  `JUMP_G` and `JUMP_V0` fall out. The apex clears THREE terrain risers where a walk gets two (`env.STEP_UP`),
  pinned in `game.zig` against `wf.HEIGHT_STEP` from both sides.
- **THE INTEGRATOR IS THE CLOSED FORM**, not `v -= g·dt; y += v·dt` — that pair loses `g·t·dt/2`: nine
  centimetres of apex at 30 fps and none at 240. A test flies all four rates.
- **GRAVITY LIVES IN `tickClocks`** — a blow mid-air routes to `updateStun` and a death to `updateDeath`, and a
  man who stopped falling because he got hit would hang in the sky. `dropActions` deliberately does NOT clear
  `jumping`. Gated on `held`.
- **IT IS `committed()`, beside the roll.** No double jump, no roll or cast out of the air, a sprint that stops
  when his feet do, and an attack pressed mid-flight BUFFERED into the one slot and fired on landing
  (`tickAir` → `fireQueued`).
- **THE STICK BENDS THE ARC AND MAY NEVER RE-PRICE IT** (`AIR_TURN_RATE`, well under `TURN_RATE`). Heading and
  ground speed are committed at takeoff.
- **HE MAY FLY OVER ANYTHING HE IS ABOVE, AND NOTHING ELSE** (`env.flyStep`, beside `walkStep`). His own FEET
  replace the riser rule, **plus the walk's own `STEP_UP` allowance** since on the takeoff frame his feet are
  still on the ground he left. **THE SAME RULE RUNS ON ALL THREE THINGS THAT CAN BE IN THE WAY, each off its
  own top**: BODIES in `collideActors` (off `topWorld`) and the world's SOLIDS in `env.resolveActor`, which
  takes his `footY` and skips any collider whose `Solid.h` is under it. `buildSolids` has always stamped that
  height and `blocksPoint`/`blocksSight` have always read it — the PUSH-OUT was the one consumer that did not.
  A wall is still a wall at any altitude (`h` 3 m against `JUMP_APEX` 1.0). **NO `STEP_UP` allowance there**,
  unlike `flyStep`: there is no step-over-props rule to stay level with. **FOES are deliberately still measured
  at `pos.y`** — nothing but the hero has a real integrated height yet.
- **THE LENS TAKES ONLY A SHARE OF IT** (`camera.LIFT_SHARE` 0.55, eased). `hero.shoulderPoint` is over the
  GROUND under him; how much of a jump the camera takes is decided once, in `camera.zig`.
- **THE POSE IS THREE TERMS OFF ONE NUMBER — the vertical velocity.** DRIVE up, TUCK where velocity passes
  through ZERO (which IS the apex, so the pose cannot drift out of step with the arc), REACH down. **The arms
  must survive the apex** (`JUMP_ARM_HOLD`) — drive and reach both pass through zero there. NO ROOT PITCH; the
  whole fold is spine and chest, and a test pins the trunk under 20° off upright.
- **THE ABSORB IS VISUAL ONLY, and that is a law.** A landing recovery that took the stick off him would be
  hitstop on the most ordinary move in the game. It is a term in `poseBody`'s CROUCH, and it OVERSHOOTS its
  rest through the shared `absorb` curve.
- **THE BEAT GOES ON THE LANDING, NEVER THE TAKEOFF.** `landed` is a one-frame flag carrying `sfx.land` + the
  ground overlay, `rumble.land` (mostly LOW against the roll's high) and `SHAKE_LAND`, which sits over a bolt
  leaving and under the lightest blow he lands. The takeoff gets a voice and nothing else. No footfalls in
  mid-air; the gait phase keeps running so he lands back into the stride he left with.

### In combat, and the quick bar

**ONE FLAG SAYS A FIGHT IS ON** (`game.inCombat`), and nothing about the HERO is in it. A creature counts if
its `foe.Leash` is ROUSED, or if he is inside the range it notices him at — **and that range is the group's own
`FoeGroup.aggro`** (a toad's world is 11 m, an archer's 24). Sight is deliberately not asked: `env.sees`
flickers as he rounds a corner. A CORPSE DOES NOT COUNT (`foe.corporeal`). **A BOSS ZONE, the day one exists**,
is the third term in that one function. `foeFights` is the per-creature term, split out so the rule has a test.

**IN COMBAT A CONSUMABLE COMES OFF THE QUICK BAR OR IT DOES NOT COME AT ALL.** The book's inventory Use is
refused while a fight is on and the panel says where to go instead.

- **THE BAR IS THE CROSS'S DOWN SLOT** (`combat.Quick`, ten entries). **The two flasks are its first two
  entries**, so a fresh game plays as it did. `Flasks` still owns their CHARGES; `combat.quickCount` is that
  split, ONE copy, asked by the HUD off the live game and by the book off its `View`.
- **CYCLE STAMPS `flasks.sel`, it does not cycle it** (`hero.cycleQuick` → `syncFlask`). `Flasks` has no
  `cycle` of its own — `Quick.cycle` is the only one, and `sel` is only ever STAMPED.
- **A REMOVAL LEAVES ITS HOLE.** A list that compacts under you mid-fight is one you cannot learn.
- **EACH BAR ENTRY IS ITS OWN SOCKET ON THE PAGE** — two rows of five, Confirm puts a kind in THAT socket
  (`combat.Quick.put`, which MOVES a kind already on the bar rather than copying). Rows are FILTERED to what
  he carries (`quickOffered`) and carry an empty row, so a kind's ordinal is not its row and `pickIndexOf`
  counts it out the way `candidates` builds it.

### Souls — the drop, and the ring that refuses it

Everything comes off him on the frame he DIES rather than at the respawn, so the spill plays under the YOU DIED
card. The currency is SOULS throughout.

- **THERE IS EXACTLY ONE.** A second death overwrites the first. Not a storage decision — a list of drops would
  delete the whole risk.
- **NOTHING ELSE SPENDS IT.** No timer, no decay, no despawn on distance. A death RE-HOMES the field
  (`game.resetFoes`) and must not touch the drop; only a change of MAP clears it (`game.armScript`).
- **RETRIEVAL IS INSTANT.** No committed action and no animation on the man. The animation is all on the DROP —
  motes solved to ARRIVE at his chest inside their own life.
- **IT IS A TREE, NOT A FLAME**, so it obeys the dead-limb law: crooked bole in three leaning segments, limbs
  rising to an elbow, drooping off their line, stopping in a BLUNT swelling. It grows over `RISE`, overshoots
  its own height and settles.
- **ONE EMISSIVE LEVEL, THREE ALBEDOS.** Vertex alpha is the emissive channel, so all three golds sit at one
  alpha and separate on hue and value alone (at two levels the shaft bands). Albedos SOLVED off a sampled
  render (`souls.EMISSIVE`).
- **IT SAYS WHERE IT IS OUT LOUD** — `souls_hum` on a RETRIGGER (`HUM_EVERY`), cut short enough that takes
  overlap.
- **THE PROMPT IS FIRST IN `game.reachable`**, ahead of the fire, the folk and a box. Its ring is the GENEROUS
  one — `souls.REACH` 2.6 against a box's 2.1, asserted at comptime.

**THE SOUL BINDING RING REFUSES THE WHOLE THING** (`item.soul_binding_ring`, DS's Ring of Sacrifice). WORN, a
death takes the RING instead of the souls.

- **IT HAS TO BE ON A FINGER**, and it is the FIRST ring socket — the leech signet's own, so the choice is HP
  back on every landed blow against keeping what you carry the once. `item.Bind` holds a socket and nothing
  else.
- **THE SNAP EMPTIES THE FINGER AND THE BAG** (`game.spillSouls`). A worn socket only NAMES a kind the bag
  holds (`hero.wear`).
- **IT IS NOT A TOOL.** `usable` false, off the quick bar. The one piece of gear spent by DYING.
- **ASKED OF THE ITEM, NOT THE KIND** (`item.bindsSouls`, read off the `Bind` payload), which is why
  `game.bindingWorn` walks every socket.
- **ONE IN THE WORLD**, in a chest, test-pinned.

### Status effects — POISON, and the shape every one after it takes

**ONE METER DOES ALL THREE JOBS** (`combat.Status`). Hits fill it; full, it **PROCS**; the same meter becomes
the **CLOCK**, draining over the effect's life while it bills HP. **It cannot be topped up while it drains** —
where a BURST status (bleed) resets to nothing and re-procs at once.

- **DECAY IS WHAT MAKES IT PRESSURE**: the meter falls once you STOP taking doses (`AilRow.decayDelay` then
  `AilRow.decay`), so spaced hits never proc and LINGERING is the whole cost.
- **A SOURCE HANDS OVER BUILDUP, NEVER HP.** A source keeps no clock of its own.
- **THE PROC IS BILLED AS A DRIP** (`Vitals.drip`): no poise. It takes the row's `hpFrac` of MAX HP over its
  span, a fraction so it is worth the same on a Vitality build as on a fresh sheet.
- **AND IT IS BILLED AS CHAOS** (`combat.poisonPulse`, PoE2's). **BUILDUP AND RESISTANCE ARE TWO DIALS AND BOTH
  ARE LIVE**: the tree's Warded Blood and `item.sporecrown` slow the METER filling (`hero.perk.poison`) while
  chaos resistance cuts each TICK.
- **THE DRAIN IS SILENT AND UNFLASHED.** The red edge and the beat belong to a BLOW. **The PROC gets the whole
  of the feedback, once** — one shake, one voice, one flash.
- **THE BAR HAS TWO FACES OFF ONE NUMBER** — violet FILLING, toxic YELLOW once it has gone off, and **nothing
  at all** while empty. Not green: it sits directly under the stamina bar.
- **A BONFIRE CURES IT** (`hero.makeWhole`), and a death is a return to one.
- **TWO SOURCES, ONE FLUID** — the sporeling's cloud (`SPORE_BUILD`), the mother's spit (`M_SPIT_BUILD`) and
  acid pools (`ACID_BUILD`). Neither floor deals damage. Spores and acid at once dose as **both** — two `add`
  calls, not a max.
- **THE METER SITS ON THE BODY, NOT ON HIM** (`combat.Vitals.ails`) — his and every creature's, filled by
  `Hit.dose` through the one `Vitals.hit` and ticked for a creature in `foe.grip` (which EVERY creature
  already called, so no foe grew a field). `Vitals.ailRate` is the dose multiplier and the ONE place it is
  applied: the tree's node and what is on his head land there through `hero.settleBody`, so the spores' door
  (`hero.poisonBy`) and an edge's cannot disagree.
- **AN ENVENOMED EDGE IS WHAT PUTS ONE IN A FOE** (`item.Arm.venom`, `item.ENVENOMED`). The dose is CARRIED
  through `Hit.scaled` rather than multiplied, like `launch`: it belongs to the coating, not to the stroke,
  so a heavy swing does not poison harder. A blow that KILLED doses nothing. Since the proc is CHAOS, every
  creature's own column already answers it — the brood's +75 takes a quarter of it, measured in a test.
- **THE FOE'S BAR SHOWS IT** (`hud.foeBar`), its own 2 px row under the cold's, violet filling and yellow
  running — a tint on a 54 px red bar is a hue nobody can name.

### Resistances — PoE2's four

- **PHYSICAL IS NOT ONE OF THE FOUR.** `Elem` is fire/cold/lightning/chaos. What mitigates physical is ARMOUR,
  its own curve — `combat.armourTaken`, `A/(A + 5*dmg)`. Do not add a "physical resistance".
- **75 IS THE CAP, NEGATIVE AMPLIFIES** (`RES_CAP` 75, `RES_FLOOR` −100). Stored uncapped, capped on READ
  (`Resists.at` vs `.raw`).
- **A SPREAD IS WRITTEN BY NAME** — `combat.resists(.{ .fire = -45 })`, matched at comptime so a rename is a
  compile error. An array literal in enum order silently shifts on a fifth element.
- **POISE AND STANCE BELONG TO THE BLOW, NOT THE BODY.** `guardChip` is damage only for the same reason. **A
  shield is billed on the RAW blow** (`Hit.raw`).
- **THREE AND A HALF OF THE FOUR ARE LIVE** — FIRE (fire arrow, tallowed sword, kobold sling clump), LIGHTNING
  (the thundercrock's alone — nothing deals it AT the hero), **COLD, which BOTH SIDES deal** (the
  necromancer's ring at him, the rod's rime breath back, both neat with no physical — `necro.FROST_HIT`,
  `combat.Chill`; a comptime assert pins the necromancer's), and **CHAOS, the one he meets most**: the wand's
  bolt and roots, the Bone Knight's lit blow and GAS, and what POISON bills in. So the sporeling cap's ward and
  the tree's Veil answer sporelings, the brood and the boss alike.
- **COLD IS THE ONLY ONE THAT DOES SOMETHING BESIDES DAMAGE** (`combat.Chill`) — a hold on the FEET, travel
  multiplied by `CHILL_TRAVEL`, taken as a post-step gate (`game.gateChill`). A chilled creature is not a
  slowed creature, it is one that cannot close. **Deliberately NOT time dilation.** **NOT SKIPPED FOR A
  FLYER** — the one place it parts company with the terrain gate beside it. **Built to be worn by EITHER
  SIDE**: it knows nothing about a foe, holds no position, bills no damage.
- Every foe carries its own table, authored where its HP is (`initFoe(..).withRes(..)`):

  | creature | fire | cold | lightning | chaos | why |
  | --- | --- | --- | --- | --- | --- |
  | gaping toad | +40 | −30 | −25 | 0 | wet out of a bog, cold-blooded |
  | skeletal archer | −35 | +60 | 0 | +45 | dry bone burns; no flesh to freeze or poison |
  | one-eyed ogre | +30 | +30 | −15 | +20 | too much mass, but stands in an open field |
  | kobold (all three) | −45 | +20 | 0 | 0 | fur goes up — the fire arrow IS the answer to a warband |
  | brood mother / broodling | −25 | +35 | 0 | +75 | chitin and its own acid |
  | egg sac | −70 | 0 | 0 | +75 | dry silk over a membrane |
  | skeletal warrior | −35 | +60 | 0 | +45 | the archer's body |
  | shade | +30 | +65 | 0 | −45 | nothing to burn, and cold is what it already is |
  | leechfly | −55 | −25 | 0 | +35 | a wing is a membrane; the chaos is what it has been drinking |
  | the Rooted | −70 | +40 | −20 | +30 | dead dry wood; lightning splits it |
  | sporeling | −50 | +15 | 0 | +75 | a damp fungus stuffed with its own element |
  | Bone Knight | −35 | +60 | 0 | +45 | the archer's body in a suit |
  | Delver | +20 | −30 | −40 | 0 | packed earth over a damp hide; a bolt EARTHS |
  | Necromancer | −35 | **+75** | 0 | +45 | cold at the cap — it is the one thing that deals cold |

- **WHAT HE OWNS ANSWERS THREE OF THE FOUR NOW** — cold off the rimeward mantle (35), chaos off the spidersilk
  moccasins (25) and the sporeling cap's ward (40), fire off the kiln draught's (40). LIGHTNING IS STILL 0 ON
  PURPOSE: nothing deals it at him, so a piece that turned it would be honestly inert.
- **A WARD AND A COATING NAME THEIR OWN ELEMENT** (`item.Use.ward`, `item.Use.grease`, both an `item.ElemName`).
  ONE column each and one at a time: a second tonic MOVES the ward rather than opening a second column, the way
  `Timed` refreshes rather than stacks. `item` is a leaf, so `combat.elemOf` is the crossing and a comptime walk
  in `combat` pins the two enums field for field.
- `makeWhole` CARRIES RESISTANCES ACROSS a bonfire.

### The character sheet (`stats.zig`)

Seven attributes; `hpFor`/`fpFor`/`staminaFor` turn Vitality/Mind/Endurance into the bars at ER's soft caps.
**The starting sheet reproduces the tuned bars exactly** — every attribute starts at 15, where the curves yield
70 HP / 60 FP / 105 stamina, so `hero.HP_MAX`, `combat.FP_MAX` and `combat.STAM_MAX` are DERIVED and a test
pins all three. **The bars take their size from the sheet in one place** — `hero.makeWhole`.

### The passive tree (`passivetree.zig`) — PoE2's, radially

Three arms out of one hub. Arms are never NAMED on screen — colour and direction carry which is which
(`Arm.ink`). Nothing is a class: all three hang off the hub, open from the first souls you spend.

**EACH ARM OPENS ON ONE CLASS NODE AND RADIATES INTO TWO BRANCHES.** `Arm.stat` is that node — the arm said in
one attribute. Six `Branch`es, two per arm in arm order (`Branch.arm` is arithmetic, pinned at comptime), each
a climb of six ending in its own keystone; 39 nodes.

| branch | what it is |
| --- | --- |
| `warrior_life` | armour, the slow refill, blood off the blade — keystone `Sanguine Pact` (leech 4.0) |
| `warrior_berserk` | the bargain, the cull, what a body is worth as it drops — keystone `Berserk` (a fifth of the bar for 1.34×) |
| `rogue_evade` | the roll, the bar behind it, poison, ground covered — keystone `Misty Step` |
| `rogue_ranged` | everything that leaves his hand — keystone `Hail` (thrown 1.55×) |
| `wizard_well` | the pool: how deep, how fast it fills, what it wards — keystone `Wellspring` |
| `wizard_cast` | how fast, how hard, and **`Chaos Bloom`** — the one keystone that is a MECHANIC |

- **A GRANT IS A NUMBER ON `Bonus` OR IT DOES NOT EXIST**, and **THE IDENTITY IS THE FIELD'S OWN** — 0 for
  anything added, 1 for anything multiplied, false for a flag. A test pins every identity, pins that the tree
  moves every one of them, and pins that **no `Grant` variant is unreachable**.
- **A BARGAIN IS STILL ONE GRANT** (`Grant.sacrifice`). Costs ADD and gains MULTIPLY; `hero.hpMaxOf` clamps the
  pair with the charms at 0.9 of the bar.
- **THE CULL IS READ BEFORE THE BLOW, NEVER AFTER IT** (`foe.Blade.cullAt`, applied in `foe.strike`) — asked of
  the HP the body walked into the swing with. Carried on the BLADE, stamped only on `game.heroBlade`.
- **THE CHAOS BLOOM IS `knight.Gas` READ FROM THE OTHER SIDE** — same type, same life, same
  `knight.GAS_DOSE_EVERY`, dosed through `pierceFoes` as a zero-length `through` blade at the cloud's radius.
  Laid at the IMPACT frame.
- **YOU CLIMB, AND THE LINK IS THE RULE** (`feeders` / `Tree.reached`). A node opens the moment ANY ONE of the
  things it hangs off is yours. `feeders` is asked by the DRAW and by `locked` alike, so the page cannot gate a
  branch on something it does not show. **The capstone is the one node with two ways in.**
- **IT RETURNS A SLICE, NOT A PAIR OF OPTIONALS.** As `[2]?usize` a one-feeder node carried a trailing null,
  every reader read that as "hangs off the hub", and the whole tree opened at once. An EMPTY slice is the hub.
- **TAKING A NODE IS THE LEVEL** — one press spends the souls and puts the node on the board. No point pool.
  `Tree.take` hands back what it charged, so `game.bonfirePick` is the one line that can bill him, and the ONLY
  thing in the game that spends souls.
- **SOULS, NEVER RUNES**, in the code as well as on the page. `combat.Souls`, `hero.souls`; `rune_arc` is a
  physical object, and `nameless_soul` is the item that IS worth souls.
- **THE PRICE IS MEASURED AGAINST A BODY.** Toad 60, archer 130, mother 240 — so `costAt` is set where the
  first node is three archers and the whole 21 is ~80k. ONE price per level whichever node it lands on.
- **SPENT AT A BONFIRE, READ ANYWHERE.** The book's LAST page is the wheel READ-ONLY; the fire's screen is
  where it is committed. `passivetree.drawPage` is ONE copy drawn by both, `spendable` the only difference.
  Tab is **PASSIVES**.
- **THE BONFIRE IS A SCREEN, NOT A PAUSE.** He sits RIGHT, the menu is a list down the LEFT: Level Up (opens
  the wheel), Memorize Spells (opens the rack), the two waits, Leave Bonfire. The wheel shows ONLY once Level
  Up is chosen.
- **GETTING UP IS A ROW ON THAT LIST, OR BACK.** "Any button" cannot coexist with a cursor. Back is the one
  button that can never also pick — off the wheel first, then out of the fire. The book and the pause card are
  BOTH refused at a fire.
- **NO HINT ROW ON THE FIRE'S LIST.** The WHEEL keeps its hints — LS/RS/zoom is not guessable.
- **THE VIEW IS PANNED, NOT SHEARED** (`game.restCamera`, `REST_PAN`). Eye and target move by the same vector
  along the camera's right axis. Screen-right is `cross(forward, up)` — `camera.rightXZ`'s law.
- **LEFT STICK WALKS THE WHEEL, THE CROSS ZOOMS, THE RIGHT STICK PANS** (`menu.stickPush`, `menu.dpadZoom`,
  `menu.stickPan`). Zoom is on the CROSS, not the bumpers — those are the book's page turn. Which is why the
  cross is WITHHELD from the walk on a wheel and kept on a list: `menu.navFor` is that decision, in one place.
  A stick is a LEVEL where a walk wants EDGES. FOUR STANDARD PIECES, all here: a RADIAL magnitude, never
  per-axis (the square's corner passes at 0.62 per axis while true deflection is 0.88); a SCHMITT TRIGGER
  (`STICK_FIRE` to arm, `STICK_REARM` to re-arm); DAS then ARR; and a DEAD CONE AT THE DIAGONALS — **ON A LIST
  OR A GRID, WHICH IS THE ONLY PLACE IT BELONGS.**
- **A RADIAL LAYOUT TAKES THE THUMB'S OWN BEARING, NEVER ONE OF FOUR** (`menu.stickPush`'s `radial`). Arms run
  out at 0, 120, 240°, so almost nothing lies along a screen axis; snapped to four axes and gated by the 32°
  dead cone, the thumb pointed AT a node landed IN the cone on two arms of three. So `passivetree.step` takes a
  HEADING (`dx`/`dy` as floats, normalised inside) and its own wedge chooses. CROSS and KEYS still hand it a
  cardinal; a LIST still takes the sign of an axis (`mathx.signI`). Two tests pin it. **A WHEEL IS STEERED, NOT
  RE-PRESSED**: a turn past `AIM_TURN` (40°) fires at once and a drift under it carries the repeat onto the
  bearing the thumb is on NOW.
- **THE FRAMING IS A SQUARE ON THE HUB, NOT A FIT OF THE BOUNDING BOX** (`passivetree.VIEW_R`). Three arms at
  120° have a bounding box whose centre is nowhere near the hub. `unit` comes off the panel's SHORT axis so it
  fits either way up, and `VIEW_R` is the outer radius of what is actually DRAWN — keystone centre at `RINGS`,
  its disc, and the breathing halo an OPEN one wears. A test pins the hub to the centre at three aspect ratios.
  **THE PAN IS LIVE AT `ZOOM_MIN`** (`PAN_FLOOR`). **THE ARMS ARE NEVER CAPTIONED, so nothing reserves room for
  one** — `CAP_OUT`/`CAP_HALF`/`onAxis` outlived the labels and went on reserving dead air the fit paid for by
  drawing every node ~19% smaller.
- **The zoom re-centres on the CURSOR** as it goes in, blended from the hub so nothing moves at `ZOOM_MIN`.
  Read as a HELD LEVEL so it glides; the pad's half is the cross alone.
- **THE MIDDLE IS A PLACE THE CURSOR MAY REST** (`passivetree.HUB`, indexed one past the last node so every
  `NODES[i]` site is untouched). It takes no press and is never a purchase — the reading column describes the
  TREE from it.
- **THE TREE OWNS THE LEVEL, NOT THE SHEET.** Level is COUNTED off the board (`spent() + 1`) and every
  attribute past the starting sheet came off a node (`Bonus.sheet`). No attribute allocation beside this; the
  STATS page is read-only for good.
- **ONE GRANT PER NODE.**
- **THE REST OF THE GAME READS FIELDS OFF ONE `Bonus`**, stamped by `game.applyTree` → `hero.applyPerks`
  (sheet + resistances + perks in ONE call). Nothing outside `passivetree.zig` walks the node list. Five
  hero-local readers: the roll's stamina, the roll's i-frames, the cast's cost, the cast's blow (`Hit.scaled` —
  the WHOLE blow) and the guard's negation (`combat.guardChip` takes the figure as an argument; a foe's boards
  pass the flat `GUARD_NEGATE`).
- **`foe.PARRY_LEAD` IS DELIBERATELY NOT A PERK.** One difficulty dial every creature's tests bracket at
  comptime.
- **THE WALK IS GEOMETRIC** (`book.slotStep`'s law) — an ordinal walk steps between nodes nowhere near each
  other. A test floods all four directions from every node.
- **THE THREE STATES SEPARATE ON FILL, NOT ON HUE** — taken is solid, open is a lit rim over the seat, locked
  is the rim gone to nothing. The arm's colour already carries the arm.
- **ONE LINK PER NODE, AND TWO ONLY AT THE CAPSTONE.**
- **THE SELECTION IS BUILT OUT OF THE NODE** and drawn last, by the wheel itself so both screens get it: a
  breathing halo standing off the disc, a hard rim on it, and the chrome's corner brackets round that. All
  three — the rim alone is lost in a taken node's fill, the halo alone in the ring circles behind it.

## Armaments

**R1/R2 (and L1/L2) BELONG TO THE ARM, NOT THE WEAPON.** Attack buttons are read as buttons and routed by which
armament is in that hand. L1 is the left hand's ACTION (block / cast), L2 its SKILL (aim / parry). Swaps: D-pad
Right / Q = sword ↔ bow; D-pad Left / F = shield ↔ wand; D-pad Up / G cycles the sorceries he has MEMORIZED, in
rack order (`combat.Memory`). The QUIVER keeps keyboard Y alone — on the pad the arrow is changed in the book's
ammo slot.

**A SELECTED VARIANT IS LATCHED WHERE THE COMMITTED ACTION STARTS**, and the selector REFUSES while one is
running. **One place answers what it costs** (`combat.spellFp`). Exhaustive switches over the selection, so a
new one is a compile error until it has said what it costs and what it does.

### The bow (`hero.zig`)

- **THE SHIELD GOING IS ANATOMY, NOT A BALANCE DIAL** — `canGuard` ASKS the arm rather than the swap clearing a
  flag. The HUD's LEFT slot goes EMPTY.
- **IT IS THE SKELETONS' BOW** — `archer.bowMesh`/`stringMesh`/`nockArrowMesh`/`poseBow` are shared and every
  stance angle is lifted from `archer.poseUpper`. The one import running against the grain (hero → archer).
- **THE AIM IS HELD, THE LOOSE IS THE ONLY COMMITTED PART** — `setAim` re-derives from `canAim` every frame.
- **AIMING SUSPENDS THE LOCK OUTRIGHT** (`game.activeLock`) — suspended, not dropped; R3 is dead while the bow
  is up. **And it slows the look** (`game.AIM_LOOK_SCALE`).
- **A BOW CHIPS; IT DOES NOT WIN.** Both shots come in under the melee they compare to, poise slighter still.
  Behind a raised bow he moves at `BOW_AIM_SPEED` (0.45 of the walk, under the shield's 0.75).
- **ARROWS ARE FINITE** — `combat.Quiver`, ten plain and five fire (`FIRE_ARROWS_MAX`), refilled at a bonfire.
  The quiver is checked BEFORE stamina is charged. The SELECTED kind is what flies, empty or not, LATCHED at
  `startShot`.
- **THE FIRE ARROW** hangs fire worth `FIRE_ARROW_FRAC` (0.5) of the shaft's physical ON TOP of it — PoE2's
  "adds X fire damage", physical untouched. Uses `.flame` and `propart`'s fire palette. Tongues, not a blob.
- **THE SHOT CONVERGES ON THE RETICLE, it does not run parallel to it.** Thrown at a point ON the camera's
  centre ray at the distance that ray REACHES (`camera.centreRay` → `game.camAimPoint`). Loft is only added
  when the target is a real point.
- **THE AIM PUSHES THE EYE IN PAST HIM AND FADES HIM OUT** — the player's own `dist` is never written, and the
  fade is LIT-PASS ONLY with the depth mask off.
- **HIS SHAFTS ARE A PIERCING BLADE** (`foe.Blade.pierce`), through each creature's own `tryHit`. It neither
  reads nor writes the swing latch.

### What he is wearing and holding (`item.Equip`, `hero.Worn`)

**BARE IS THE GAME EXACTLY AS IT WAS.** Every dial on an `item.Arm` defaults to 1 and the armour curve of 0
armour is the blow itself. A new game is bare-handed (`STARTING_KIT` is the wolf scroll alone).

- **ONE TABLE, ONE ROW PER THING** (`item.equip`) — nineteen pieces, and the numbers are all any of them is (a
  test counts the worn ones). Gear shelves as `Class.gear`, and the bag panel prints the row (`item.effect`),
  A CLAUSE PER DIAL rather than a sentence per combination — four dials on a `Plate` is sixteen sentences.
- **A PLATE MAY MOVE HIM TOO** (`item.Plate.move`, the spidersilk moccasins' 1.06). Multiplied onto the tree's
  node in `hero.moveRateOf`, which `game.moveHero` is the only caller of, so a shoe that hurries him cannot
  reach one movement path and miss the others. **STRICTLY WORSE ARMOUR ON PURPOSE** where it buys a column and a
  pace: a piece better than the boots beside it on every dial retires them instead of competing.
- **EVERY SOCKET ON THE DOLL IS REAL, AND A COMPTIME WALK KEEPS IT THAT WAY.** `item.zig` fails to compile if a
  non-hand `Wear` has no kind that goes in it, and `book.wearOf` is the ONE place a doll slot becomes an
  `item.Wear`. A faint socket is a fact about his BAG, not about the world.
- **BOTH FINGERS ARE THEIR OWN SOCKET, AND THE RINGS ARE SPLIT ACROSS THEM** — the bloodtinge signet (+5
  Vitality) is a `ring` and the loop of chance (+4 Luck, the only thing that moves `stats.findFor`) a `ring2`,
  so the pair can be worn at once and neither shares a socket with the other's attribute.
- **A SOCKET MAY BUY A SKILL** (`item.Boon`) — `n` points of an attribute, folded onto the live sheet by
  `hero.boonsOnto` through `hero.resheet`, which is THE place the sheet is built: the tree plus what he has on.
  `applyPerks` assigning the sheet straight from the bonus is how a belt got wiped off it by buying a node. A
  plain grant with no cost where `Charm` is a bargain; a boon of an INERT attribute is a compile error.
- **A SKILL DRIVES A BLOW THROUGH THE DAMAGE DIAL AND NOTHING ELSE** (`stats.scaleFor`, `hero.scaleOf`,
  `item.Scaling`). One curve for strength/dexterity/intelligence, ER's 20/55/80 caps, and **1.0 at
  `stats.START` exactly as the bar curves are** — the licence for wiring damage to an attribute without
  retuning a tuned constant. A weapon names ONE skill (club strength; dirk and warbow dexterity; plain sword
  `quality`, the mean of the two); the rod is intelligence, taken in `castBlow`. Poise and stance stay the
  WEAPON's mass. **An EMPTY socket gets `item.bareArm`, not `Arm{}`** — the sword's `quality` default inherited
  by a bare bow paid a bowman for strength.
- **A WEAPON IS PRICED AS MULTIPLIERS ON THE ARMAMENT IT FILLS, NEVER AS FRESH ABSOLUTES.** `hero.ATK_*_HIT`,
  `combat.STAM_*` and `combat.GUARD_*` stay the one place a swing, a block and their bills are written down.
  **THE DIALS ARE NOT ALL THE SAME WAY UP** — `dur` and `stam` are BILLS, so under 1 is the gain there.
- **A WEAPON SAYS WHAT KIND OF WEAPON IT IS, ON TWO AXES** (`item.Heft`, `item.Reach`). REACH is pinned to the
  socket at comptime; HEFT is how much of the body goes into it, and it is what the page prints.
- **THE STROKE IS ONE STROKE, SCALED** (`hero.Move`/`moveOf`, three multipliers over `AL_*`/`AH_*`). A
  club gathers further back, drops lower in the hips, carries further through; a dirk is the same stroke shut
  down to the elbow. **THE PLAIN SWORD IS 1 ON EVERY DIAL.** A test pins the table against `heft`.
- **THREE SHAPES ON ONE GRIP** (`hero.Blade`, `BLADES`, `bladeOf`). Dirk and club are the SWORD bone with
  another mesh and capsule — 0.67 m and 1.44 m of reach against the sword's 1.15 — so pose, trail, sparks and
  every window are written once. **THE SHAPE IS LATCHED AT `startAttack`** with the row.
- **WHAT A ROW DOES TO A BLOW IS ONE FUNCTION** (`hero.weigh`), asked by the sword, the bow AND the book. The
  ELEMENTAL half rides the damage dial and the STANCE rides the poise dial. Tallow is applied AFTER the row.
- **THE CLOCK MOVES WITH THE WEIGHT** (`hero.atkDur`), and the POSE reads the same clock.
- **ARMOUR IS THE FIFTH COLUMN AND IT IS A CURVE** (`combat.armourTaken`, PoE2's). Worth most against small
  blows and least against the one that was going to kill you, so it can never become immunity and needs no cap.
  PHYSICAL ONLY, and it touches NEITHER POISE NOR STANCE.
- **A BOARD MAY NEVER STOP A BLOW OUTRIGHT** (`combat.GUARD_NEGATE_CAP`).
- **A CHARM RESIZES THE RED BAR, AND THE FRACTION IS KEPT ACROSS THE RESIZE** (`hero.refitHp`). Done through
  `hero.wear`, not at the next bonfire.
- **A SOCKET REFUSES WHAT DOES NOT BELONG IN IT** — `hero.wear` and the save's parser both ask
  `item.wearSlot`. Seated wrong, every dial reads as 1 and the piece silently does nothing.
- **THE PICKER OFFERS BOTH AXES AS ONE LIST** (`book.Hand`): every armament, and under each the gear he is
  CARRYING that fills it. So the row has to be COUNTED rather than taken as an ordinal (`book.pickIndexOf`).
  The VARIANT is the ARMAMENT'S, not the hand's.
- **THE VARIANT IS NOT REFUSED WHEN THE HAND IS** (`game.takeHand`) — `hero.equip` says no mid-swing, and a
  socket left saying "club" over a fist still swinging a sword is the page lying.
- **THERE IS ONE OF EACH, AND THE RACK IS FOUR CELLS** (`hero.equip`). One sword, one board, one rod. Taking a
  thing already racked SWAPS the two cells rather than refusing; `hero.tidyHands` fixes a save written before
  the rule (`save.scatter`).
- **THE CELL DRAWS WHAT IS IN IT, NOT WHICH ARM IT IS** (`hero.heldGear`, asked by `hud.Slot` and
  `book.handArt`).
- Saved as one `worn:` line, ABSENT from an older file, which loads as bare.

### The wand (`hero.zig`) — the first thing that spends FP

- **A CAST IS COMMITTED, NOT HELD** — the FP is gone the moment it starts, so it lives in `committed()`, is not
  buffered, and a stagger drops it with the charge spent. He is PLANTED for it.
- **BILLED IN FP AND NOTHING ELSE** — `BOLT_FP` 12 of 60. The wand competes with the flask, not with the roll.
- **PAY OR CAST NOTHING** (`Focus.spend`) — the INVERSE of stamina's panic rule. `hero.fpRefused` →
  `hud.refuseRing`.
- **THE ARM GOES OVERHEAD AND SWEEPS ACROSS THE TOP**, repeated casts sweeping OPPOSITE ways (`castAlt`,
  flipped at the START of each cast). `rz` swings the left arm through the frontal plane and 180 is straight up,
  so raise and stroke are ONE channel: overhead ± `CAST_SWEEP` (34). `CAST_SH_FWD` (36) tips the plane forward.
- **THE ARM GOES LONG AT THE THROW** — a folded elbow keeps the stone inside his own silhouette.
- **THE ROD IS NOT A BONE** and has NO fit matrix: authored in the left wrist's frame along −Y. `wandTipWorld`
  is MEASURED off the mesh's constants (the ogre's `clubLowWorld` law).
- **THE BOLT FLIES THROUGH THE ARROW POOL** (`archer.Shot.bolt`) — cover, gravity, ground, expiry and the swept
  `pierce` test are one body of code.
- **ALL CHAOS, NO PHYSICAL** — `BOLT_HIT` 24 chaos, poise 14, stance 6. Chaos is the most-resisted column, so
  the wand answers toads and kobolds and is near useless against skeletons. An honest trade.
- **ONE VIOLET FOR THE WHOLE SPELL** — stone, gather, both bursts, streak and LIGHT.
- **THE STONE IS THE ONLY LIGHT IN THE GAME THAT MOVES** (`hero.wandLight`). `env.uploadLights` takes it as a
  RESERVED slot, so a brazier he is standing beside can never evict his own spell. Point light is MULTIPLIED by
  albedo here — loud on marble, muted on grass.
- **THE GATHER RIDES THE HAND AND ITS LIFE IS WHAT PAYS FOR IT.** Motes are solved to ARRIVE at the stone, and
  the stone crosses 1.5 m through the lift. Adding the tip's velocity fixes the constant part; the leftover is
  ½·a·life², so the correction that matters is a SHORT LIFE — and `drawParticles` fades radius with alpha, so a
  short life is bought back with RADIUS, never with more motes.
- **THE RELEASE IS A CONE, A COLLAR AND ONE FLASH.** The cone alone is indistinguishable from the bolt's first
  metre; the collar thrown sideways out of the bolt line is what says the stone LET GO. The flash is a SOLID
  sphere, not additive.
- **THE CHARGE RISES IN THE GRIP, AND A `rumble.Event` CANNOT RISE** — a `Motor` decays from its peak. So the
  raise is pulsed every frame with a peak scaled by `hero.chargeFill` (`rumble.castCharge`), 0 past the throw.
  The release is a crack (`cast_throw`) and a frame shake UNDER the lightest one a landed blow gets.
- **TWO VOICES, ITS OWN** — `wand_charge` climbs and must RESOLVE at the throw (0.40 s against a 0.30 s raise),
  `wand_cast` is a struck-crystal crack. Nothing done with a rod is a throat.
- **THE HARNESS HAS TO FIRE THE RELEASE ITSELF.** `castToThrow` drives the POSE past the throw without going
  through `game.throwBolt`, so `throwBoltForShot` throws the sparks too. `castToCharged` stops one frame
  earlier — the only frame the gather's ramp and the light's swell can be judged on. `releaseSpellForShot` is
  the same door for the two STRIKES.

### The two sorceries that DO NOT CROSS THE GROUND — LEVIN and SIPHON

These arrive on ONE body on the frame they are cast. There is no flight to intercept, and SIGHT stands in for
one (`env.sees`).

- **THE LADDER IS MONOTONE, AND THAT IS THE WHOLE PRICE LIST**: bolt 12→24, levin 16→16, roots 18→14, siphon
  20→13, rime 22→10.2. Every step up in FP is a step DOWN in raw damage — what the difference buys is a
  stagger, a hold, HP back, or a second body in the cone. A comptime block asserts it over every PAIR, so a
  sixth spell is priced by the rule without editing it.
- **THE LEVIN BUYS THE STAGGER AND NOTHING ELSE.** Poise 34 — past every creature's `POISE_MAX` bar the
  knight's 78. Its STANCE stays under his own heavy swing's. First lightning anything but a thrown jar deals.
- **IT DOES NOT TRAVEL BECAUSE THE ELEMENT DOES NOT** (`elemfx`'s lightning: shortest life by 3×, no gravity).
  The travel comes from WHERE THE SPARKS ARE PUT — laid along the blow's own segment, all on the landing frame.
- **THE SHORT LIFE IS BOUGHT BACK WITH RADIUS, NEVER WITH MORE MOTES** (measured off a render). The landing
  burst is held UNDER the stroke's own scale — at 7 cm a mote is a soft ball and a shower reads as SMOKE.
- **THE STROKE LEANS, AND THE LEAN IS MECHANICAL** (`game.strikeSegment`). `foe.strike` takes the shove and the
  facing snap off the segment's XZ bearing, and a plumb line has none.
- **THE SIPHON FEEDS OFF WHAT THE BODY ACTUALLY LOST**, never off what was thrown at it
  (`combat.SIPHON_SHARE`) — so resisted damage is resisted healing and a skeleton is a bad meal.
- **IT IS A DRAIN, NOT A BLOW**: no poise, no stance (`Root.tick`'s law).
- **ITS EFFECT RUNS THE WRONG WAY UP THE LINE** — motes off the BODY, solved to arrive at the stone inside their
  own life, which is `souls.zig`'s construction with the ends swapped.
- **ONE PLACE ANSWERS WHAT A SPELL LANDS** (`combat.spellBlow`), null for the two that bill over time.

### The memory slots (`combat.Memory`, `rest.zig`, `book.zig`)

Every spell is written on a SCROLL (`combat.SpellRow.scroll`, an `item.Kind` that `item.isSpellScroll` claims),
and the rod casts only what is in the RACK — three slots (`combat.MEM_SLOTS`) filled at a fire.

- **THE RACK IS THE ONLY LIMIT, AND IT IS ONE NUMBER.** Nothing else counts the cells; widening it is one edit.
  **A NEW CHARACTER HAS THE BOLT AND TWO HOLES** (`Memory{}`'s default).
- **CARRYING THE SCROLL IS THE WHOLE GATE, AND MEMORIZING DOES NOT SPEND IT.** The bag is asked and never
  emptied. The seven sheets are in `game.STARTING_KIT`; where a scroll is FOUND belongs to the map and the drop
  table.
- **THE RING IS THE RACK, NOT THE TABLE** (`Memory.next`, `hero.cycleSpell`). D-pad Up walks what is memorized
  IN SLOT ORDER. One in the rack is nothing to cycle to.
- **A SPELL ALREADY IN ANOTHER SLOT MOVES RATHER THAN DOUBLING** (`Memory.put`).
- **THE SELECTION IS A FINGER ON THE RACK AND FOLLOWS IT** (`hero.armed`, `hero.tidySpells`; `memorize` is the
  ONE door that moves either). Empty the rack and `canCast` refuses, the HUD cell goes empty, and
  `game.castWand` says "Nothing memorized." rather than eating the press.
- **THE FIRE IS WHERE IT IS COMMITTED AND THE BOOK IS WHERE IT IS READ.** `Memorize Spells` is a row on the
  fire's list (`rest.Row.memorize`); the book's SPELLS page is READ-ONLY.
- **THE FIRE'S SCREEN IS TWO STAGES, THE EQUIPMENT PICKER'S EXACTLY** (`rest.memRow`/`memPick`): a slot, THEN
  what goes in it, opening on WHAT IS IN THE SLOT — counted, never an ordinal. An empty row is always offered;
  a slot with nothing to put in it does not open.
- **A SORCERY HE HAS NO SCROLL FOR IS DIMMED, NEVER HIDDEN.**
- **ONE SCROLL PICTURE, AND THE DRAWING ON IT SAYS WHICH** (`itemart.sorceryScroll`) — `spellArt` inked at a
  third size, so the sigil the HUD shows is the sigil in the bag.
- **THE FILE CARRIES THE RACK AND NOTHING DERIVED** (`memory:`). Absent from an older file it loads as the
  STARTING rack, an unknown tag is a LOAD ERROR, and a file with more slots than this build drops its tail —
  `MEM_SLOTS` may narrow. A comptime block pins that every spell names a scroll, no two share one, and no
  scroll is unwritten.
- **THE HARNESS MEMORIZES RATHER THAN CYCLES** (`game.selectSpellForShot`).

### The torch (`hero.zig`)

**IT IS A RACK CELL, NOT A KEYBIND.** `Armament.torch` is a sixth thing the book's four hand cells can hold. One
torch in this world, so `wearFor` gives it no socket.

- **WHAT IT COSTS IS THE HAND, AND NOTHING ELSE.** No stamina, no FP, no action on either button (`handActs`'
  one empty prong). Nothing refuses a guard for holding one — `canGuard` asks `shieldOut` and gets its answer
  from the rack, so in the LEFT cell the boards are gone and in the RIGHT the sword is.
- **THE LIGHT IS RESERVED** (`hero.torchLight` → `game.reservedLights`), beside the rod's stone. `TORCH_LIT` is
  the world torch's row opened out — a fifth again the colour at 8 m instead of 6.
- **IT GUTTERS OFF THE SAME CURVE AS EVERY OTHER FLAME** (`mathx.gutter`): three incommensurate rates.
- **THE FLAME IS DRAWN IN WORLD SPACE, THE BRAND ON THE WRIST.** The shader's flame billow throws along the
  MODEL's +Y (`sceneVS`, mat 11) — hung off the wrist it would lash sideways when he turns his arm over.
- **THE CARRY WAS SOLVED, NOT EYEBALLED.** Brand gripped SQUARE across the fist (90°, where the rod sits at
  55). Arm angles swept for the pose that puts the flame at the crown, off the shoulder line, in front of the
  chest: 1.78 m up, 0.38 m to the side, 0.30 m in front, 18° off plumb. The test prints all four with a window
  round each.
- **ITS VOICE IS A BED, NOT A PLACED SOUND** (`audio.torch_fire`, driven by `sfx.setTorch`) — centred stereo on
  the rain's machinery. Nine pops a second, redrawn every pop: a crackle is Poisson, not a metronome.

## The world

### The map is data, and the editor owns it

`worlds/*.world` are versioned text files of authoring OPS (`worldfmt.zig`); `env.materialize` replays them.
Nothing about the world is authored in Zig. Ops: `at`, `belt`, `disc`, `ring`, `line`, `ivy`, `edge`, `cover`,
plus `zone`/`clear`/`runway`/`foe` tables. Beside the shipped map, `02_brood_arena` and `03_bone_court` hold one
fight each; a test loads and replays all of them.

**`worlds/test_*.world` are BENCHES, not content** — one per thing being built, loaded with `--map
worlds/test_x.world` (and `--shot` with it). Nothing under test goes into the shipped map to be looked at.
`test_foggate` is the gate at three sizes and yaws plus a channel dug to 1.31 m, the one depth the hero can
cross and nothing on foot will follow him into.

- **A GENERATOR OP IS FOR STAMPING, NOT FOR KEEPING.** It is ONE thing to select, move and delete, so a wood
  of 260 attempts was one tree — the same complaint that baked ground cover down to `at:` decor. Stamp a
  `belt`/`disc`/`ring`/`line`/`ivy`, re-roll it until it reads, then **break it apart** (op panel, or the
  right-click menu) and it becomes one `at:` per instance, standing exactly where it stood: `env.explodeOp`
  writes down the props the replay already made, and an `at` replays at the same `groundY(x, z)` every
  generator plants on. There is no way back but undo — the seed and the shape go with it.
  `zig-out\bin\zig-soulslike.exe --explode <map>` does the whole file headlessly and verifies itself by
  re-loading and re-replaying: same prop, solid and light counts or it refuses. **`01_fallen_plain` is
  ALREADY BROKEN APART** — 13,923 ops, 215 of them groups, became 16,654 `at:`.
- **EVERY GENERATOR OP CARRIES ITS OWN SEED.** One shared stream meant inserting a belt re-rolled every op
  after it. Load-bearing.
- **ORDER IS MEANING.** Ops replay in file order because later ones read what earlier ones placed.
- **ONE FIELD TABLE DRIVES THE WRITER AND THE PARSER** (`fieldsOf`), walked at comptime in TABLE order.
  `std.meta.fields(Op)` reads the STRUCT's order and silently writes the wrong column. Unknown keys and missing
  fields are LOAD ERRORS; a missing or broken map PANICS with file and line.
- **FLOORING IS TWO GRIDS** — `soil` (material id) and `soilCov` (coverage 0..255). An edge is where the author
  left coverage low. The paint rule is `lerp(here, opacity, falloff)`: painting below what is there THINS it and
  repeated passes converge. A cell holding a different material is CONTESTED — the stroke wins only where it
  would cover more. `BRUSH_CORE` (0.55) keeps the middle solid.
- **HOW A PATCH ENDS IS PAINTED, NOT DERIVED** — a third grid (`Map.soilEdge`, one `wf.Edge` per cell), picked
  in the brush panel like the radius and the opacity. It is the STROKE's and not the material's. Eight shapes —
  `blend`, `natural`, `frayed`, `jagged`, `straight`, `tiled`, `scallop`, `speckle` — and their ordinals are
  pinned to the shader's `edgeShape()` by a comptime assert.
- **AN EDGE HAS THREE KNOBS**: how far the lookup WANDERS off the authored line, at what WAVELENGTH, and
  whether the boundary CUTS or feathers. The policy is read FIRST, at the unwarped position, because the warp is
  what the policy decides. (The old `hardEdge` bool reached only the last, and the wander was applied to the
  material ID *before* anything was asked, so nothing could produce a straight edge.)
- **THE EDGE MAP IS DILATED ONE CELL AT UPLOAD** (`gfx.dilateEdges`). A boundary is drawn from both sides and
  the shader must read the same policy either way. POINT-sampled for the id map's reason: a bilinear read
  halfway between `tiled` and `jagged` is an ordinal nobody authored.
- **A CELL IS 5 m** (`SOIL_N` 112 over a 560 m world), the floor on how fine any of this can be. Warps under
  about half a cell do not survive the coverage staircase.
- **AN OLD MAP COMES UP UNCHANGED** — no `soiledge:` row means every cell takes the edge its material used to
  imply (`fillLegacyEdges`: stone cut, everything else soft). The row is only written when some stroke asked for
  something else (`edgesAllDefault`). **WATER'S COAST DOES NOT USE ANY OF THIS YET** and may not use it the same
  way: the water field is ONE field feeding the look *and* the wading, so an edge warped in the shader would put
  the coast you see somewhere other than the coast you walk into. It has to be baked into the field in
  `env.uploadWater`.
- **WATER IS PAINTED, ITS COAST DERIVED** — one bit per cell → a signed distance field (128 is the waterline).
  One field, three effects. The sheet is ONE world-spanning quad.
- **PROPS CAN LEAN** (`lean`/`leanDir`) about the prop's GROUND ORIGIN, so the base stays planted and the
  culling sphere is unchanged. `buildSolids` carries the footprint with it.
- **`buildSolids` RESETS** — `materialize` runs it twice and an appending version doubles every collider.
- Props carry the index of the op that placed them, which is what makes a generated rock selectable.
- **A MULTI-LINE RECORD ATTACHES TO THE ONE ABOVE IT** — `when:`/`do:` to the last `trig:`,
  `who:`/`say:`/`act:`/`then:`/`ask:` to the last `node:`, `need:`/`gets:` to the last `ask:`. A part with
  nothing above it is a LOAD ERROR. `act:` may not be written after a choice.
- **PROSE LIVES IN ONE ARENA** (`Map.dtext`, `Span`). `#` still starts a comment, so no authored line may
  contain one.

  ```
  flags: met_wanderer heard_of_gate      # interned at load; the file stays self-describing
  npc: wanderer -4.50 7.50 128.0 1.00 0.31 roam=1.8 dlg=wanderer
    call: The Wanderer
  dlg: wanderer
    node: root
    say: Another one walking north.
    ask: What lies north? -> north
    ask: Then why do you sit here? -> why
    need: flag heard_of_gate=1           # gates the ask ABOVE it
    ask: (say nothing) -> end            # `end` is reserved: it closes the conversation
    node: north
    say: A gate the size of a hill, and shut.
    act: flag heard_of_gate=1            # fires when the node is SHOWN
    then: root
  trig: wanderer_seen pri=10             # once=1 by default; once=0 or a `preserve` action keeps it
    when: near npc=0 r=3.5
    when: flag met_wanderer=0
    do: flag met_wanderer=1
    do: text Someone is sitting at the bonfire.
  ```

  **`npc:` RECORDS ARE APPENDED, NEVER INSERTED** — `near npc=0` is an INDEX into that table, so putting a new
  person above an existing one repoints every condition after it. `foe:` and `wf.FoeKind` have the same rule.

  Conditions: `always`, `never`, `flag N=0|1`, `counter N <cmp> n`, `timer N=done|running`, `elapsed <cmp>
  secs`, `region x z x1 z1`, `near npc=i r=m`, `talked dlgId`, `deaths foeKind <cmp> n`, `alive foeKind <cmp>
  n`. Actions: `dialog dlgId`, `text …`, `flag N=0|1|flip`, `counter N set|add|sub n`, `timer N=secs`, `wait
  secs`, `preserve`. `<cmp>` is `<` `<=` `=` `>=` `>`.

### The day (`daynight.zig`)

One number — `Game.day.hour` — and every colour and shadow in the world is a function of it.

- **ONE DIRECTION CASTS AND THE SHADER KEYS OFF IT**: `keyDir` is the SUN while it is up and the MOON once it is
  down, `gfx.Scene.setHour` its only writer, moving `gfx.sun` and `gfx.sunReach` together. Sun rises at 6 on
  bearing 100 and sets at 20 on 262; the moon is the ANTI-SUN, so the world is never unlit.
- **THE SKY DRAWS THE TRUE PATH, THE SHADOWS DO NOT.** `keyDir` FLOORS the casting altitude at `KEY_ALT_MIN`
  (15°) while `sunDir`/`moonDir` keep the honest angle for the disc. A 2° sun throws a 300 m shadow the 108 m
  ortho box cannot hold. The one place the two are allowed to disagree.
- **THE TEXEL SNAP IS TAKEN IN THE LIGHT'S OWN BASIS** (`gfx.lightBasis`). A world-axis snap stops snapping
  under a sweeping sun and the shadow edges crawl.
- **`Palette` IS THE WHOLE LOOK OF AN HOUR**, keyframed at nine hours and blended with the ease taken off both
  ends. Retuning means moving a row, not a shader.
- **ITS TWO HALVES ARE ON DIFFERENT SCALES.** `key`/`ambGround`/`ambSky`/`haze`/`hazeBank` are read by the SCENE
  shader, which gammas its output — PRE-GAMMA and near-black. Every `sky*`/`cloud*` value is read by the SKY
  shader, which gammas nothing — LITERAL SCREEN VALUES. **At the dark hours `haze` must sit UNDER what the
  ground is lit to**, or the distance is brighter than the foreground.
- **THE ANCHOR IS NOT A KEYFRAME.** `SHOT_HOUR` (17:27) reproduces `gfx.SUN_DIR` — the light this game was
  authored, measured and photographed under, and the bearing `shots.LIT_YAW` is framed off. `SUN_ALT_MAX` and
  `SHOT_HOUR` are SOLVED from it; move `AZ_RISE`/`AZ_SET` and you solve them again. Two tests pin the direction
  and the palette row. `--shot` pins and FREEZES that hour (`game.pinHourForShot`).
- **The controls.** Menu > Debug > `Hour` (Left/Right scrub, Shift coarse, hold to sweep, Confirm holds it); in
  the EDITOR `,` and `.` sweep it and Shift runs (the clock is held there, so those are the only writers) — and
  the same hour is on the World card, as a readout, a quarter-hour stepper and four marks worth authoring at,
  `Anchor` among them. A BONFIRE offers `Rest until morning` / `Rest until evening` — always FORWARD
  (`hoursUntil`). Nothing is restocked there: `hero.sit` made him whole when he sat down. **EVENING IS AFTER
  DARK**: morning 8:30, evening `EVENING_HOUR` (9 pm, an hour past `SUNSET`, sun DOWN and moon casting).
  Deliberately NOT `SHOT_HOUR`. A comptime assert pins it past the horizon, a test pins `!isDay` and the key
  under a quarter of the anchor, and `shots/147` is that hour.
- **THE FIRE TOUCHES THE CLOCK NOWHERE ELSE.** The old `dim` uniform is GONE: the hour you walk in at is the
  hour you sit in, and the two `Rest until…` rows are the only thing at a fire that moves the light.
- Verify with the strip: `shots/140`–`147` are eight hours of ONE view shot into the light's own quarter,
  `148*` three overheads. The arc is the test — a frame that reads like its neighbour is an hour the palette is
  not earning.

### The weather (`weather.zig`)

**IT IS AN EVENT, NOT A SETTING.** A storm arrives every `DRY_LO`..`DRY_HI` (150–420 s), runs
`WET_LO`..`WET_HI` (55–145 s), ramps 9 s in and 14 s out. Measured over an hour: **9 storms, raining 26% of the
time, dry gaps 162–405 s**. The clock is PURE (`Weather` is seconds and 0..1), so a test runs a day without a
window.

- **TWO STRENGTHS, AND ONLY THE HEAVIER HAS A SKY.** `GENTLE_TOP` 0.52 against `MODERATE_TOP` 1.0, and the
  moderate storm is the minority (`MODERATE_ODDS` 0.38). Lightning waits for the storm to arrive (`FLASH_AT`).
- **A STORM BREATHES WHILE IT IS THERE.** `gustAt` is two slow swells on periods that do not divide (17.5 s and
  30), riding the top DOWN by at most `GUST_DEEP` — a moderate storm measures 0.70–1.00 of full. It rides the
  TOP and not the level, so the ramp still owns how fast the sheet may move. The lull bottoms out over
  `FLASH_AT` on purpose.
- **THE STRIKE IS A DOUBLE AND THE THUNDER IS LATE.** `flash()` is a spike, a dark beat, then a lower second
  flicker. The sound is behind the light by the strike's own distance (`STRIKE_LO`..`STRIKE_HI` over
  `SOUND_MPS`, 1.7–7.5 s), and it arrives even if the rain has stopped.
- **THE PICTURE IS ONE MESH** (`Rain`) — a cell of `STREAKS` streaks one `CELL_H` tall, drawn STACKED up the
  camera's column and slid by a phase that WRAPS on the cell; the heavier storm draws the same cell again,
  offset. **7,200 triangles in the cell, 4 draw calls gentle and 7 moderate**, test-pinned. Rain as PARTICLES
  would be thousands of live motes at one immediate-mode sphere each.
  - **WHAT COSTS IS FILL, AND FILL IS DENSITY** — streaks per square metre, which a test prints. **0.55/m² out
    to 24 m** at `OPACITY` 0.26 (from 1.97/m² at 0.44). Spreading the disc IS the thinning: streaks are laid by
    area, so trebling it drops the near field by the same factor while the count barely moves.
  - **THE COLUMN STANDS ON THE MAN, NOT ON THE LENS, AND ITS RIM FADES.** Centred on the camera the disc reached
    24 m behind the lens and 19 ahead of the hero — the short side being the side the frame looks at; and it
    must be a point the camera does not ROTATE, since a lead off the camera's forward slides the sheet sideways
    at 40 m/s when you turn. The rim thins to nothing past `TAPER_FROM` (width goes out, length only part way),
    baked into the geometry because a per-streak opacity is the one thing this renderer has no channel for. The
    heavy sheet's second copy is offset in Y, barely in XZ.
  - **THE HEAVY SHEET FADES IN, IT DOES NOT ARRIVE** (`copyFade`, 3.6 s up, 5.6 s out, topping at `COPY_TOP`
    0.72), so the peak storm is 6.16 columns of blended fill rather than 8.
  - `FALL_MPS` is 13, just over real rain's 7–9. At 21 a streak crossed twenty-three times its own body in a
    second, which is a smear.
  - **A STREAK IS TWO CROSSED CARDS** — a single card is invisible edge-on. Two segments each, so the tail
    fades in the GEOMETRY (`propfx`'s pillar law).
  - **THE SLANT IS WORLD-FIXED** (0.30 across the fall) so turning the camera turns the rain, MEASURED off the
    first shot where 0.17 read as vertical.
  - Draws LAST, through `Scene.beginFade`: no depth written, still depth TESTED, which is what puts it behind
    the wall you are standing under.
- **THE CLOUD TAKES THE LIGHT, AND THE STRIKE GIVES IT BACK** — two rectangles over the frame, INSIDE the retro
  pass. `DIM_MAX` 0.17 of a cold slate; the flash at 74/46 alpha.
- **BUT THE STORM IS A LAYER ON THE PALETTE, NOT A RECTANGLE** (`daynight.overcast`). Cloud does four things a
  rectangle cannot: puts the KEY out (`STORM_KEY` 0.34, so shadows and every `keyAmt` specular go with it),
  leaves the AMBIENT alone (an overcast sky is one enormous soft source), takes the WARMTH out (`slate` is
  luma-preserving, so a hue change and not a dimmer), and CLOSES THE DISTANCE (haze colour lifts,
  `gfx.HAZE_STORM` multiplies density by 2.4). Every term is a factor on the HOUR'S own value, never a
  constant. `Scene.setHour`/`Sky.setHour` take the level, so dome and world agree.
  - The fog distance has a DEBUG override (`menu.DBG_FOG`: Auto / Off / Thick / Soup). The row answers TWO
    questions: `fogK` is the haze DISTANCE, `fogAmt` is how foggy it IS.
- **THE FOG HAS A SHAPE: THE STRAY BANKS** (`weather.Mist`). Seven banks standing in the field, so fog is
  somewhere you walk through rather than a value. **THE GRADIENT IS IN THE GEOMETRY**: one bank is 22 lumps
  scattered with density falling off outward, so alpha compounds in the middle and thins at the rim (vertex
  alpha is the EMISSIVE channel, and three concentric shells would read as three rings). One draw per bank, 7
  draws, ~10.8k tris, `MIST_TOP` 0.17 at full fog. **THE SLOWEST THING IN THE GAME** — 0.045–0.16 m/s, 94 s to
  cross its own width. Banks ramp in and out over 9 s and are re-seeded out past `MIST_R`, never in view. Three
  mesh variants (the repeated-big-prop law).
- **THE BED IS THE STORM'S, NOT THE HOUR'S** (`audio.setRain`, `audio.mkRain`) — three bands with a granular
  patter (a hiss alone is tape noise, a low roar alone is a motorway). Does not retrigger while dry. Thunder
  (`mkThunder`) is a ROLL with no transient at its head, and it is the third kind of ambient voice
  (`AMBIENT_EVENTS`): not a bed, not a call, fired by the world.
- Weather does not run in the EDITOR, and `--shot` forces one: `shots/150`–`153` are dry, gentle, moderate and
  the strike, `154`–`155` the fog and one mist bank — forced through the debug row (`game.forceFogForShot`) so
  the air is photographed APART from the rain.

### Elevation

The world is a HEIGHTFIELD you sculpt (Ground layer > Raise/Lower/Smooth/Flat), stored as one QUANTISED height
per lattice point (`HEIGHT_N` 2.5 m, `HEIGHT_STEP` 0.25 m, biased so `HEIGHT_ZERO` is the old flat ground).
Quantised because the file is TEXT and the writer is a run-length encoder. The mesh is TILED (`TCHUNK`), with
normals from the FIELD so two tiles agree at their seam.

- **A FLAT MAP IS THE OLD WORLD, EXACTLY** — `heightAny` false means one world-spanning quad, `groundAt`
  returns `GROUND_Y`, and no `hgt:` record is written.
- **NOTHING SAMPLES THE MAP DIRECTLY.** Env keeps the live copy the visible mesh was built from and
  `wf.sampleHeight` is the ONE sampler both owners call.
- **EVERY PROP PLANTS AT THE HEIGHT UNDER IT** — `uploadHeight` must run BEFORE `materialize`, and a sculpt
  stroke re-materializes on RELEASE.
- **TWO RULES DECIDE EVERY STEP** (`env.walkStep`), either passing: the rise ahead is under `STEP_UP` (0.55 m,
  sized to the encoding — two risers walkable, three a wall), or within `MAX_SLOPE` (tan 40°).
- **MEASURED OVER A FIXED LOOKAHEAD (`STEP_PROBE`), NEVER THE FRAME'S OWN TRAVEL.** Against frame distance a
  240 fps hero ratchets up a vertical cliff. A test pins the rule across four frame rates.
- **A REFUSED STEP IS NOT A STOP** — the uphill component is removed and the rest is taken at full length.
- **FOES GET THE SAME RULES** as a POST-STEP GATE (`game.gateTerrain`). Airborne foes are exempt from the
  terrain rule and from being shouldered — never from `env.resolveActor`. That push-out is NOT rate-limited.
- **BUT NOT AT HIS WATERLINE — AT THEIR OWN** (`foe.wadeLimit`, `env.walkStepPast`). `WADE_MAX` 1.37 m is CHEST
  height on the 1.8 m rig and HIS choice. A creature turns back at `foe.WADE_FRAC` (0.45) of its own stature,
  read off `topWorld`. **THE WATER IS A DOOR FOR EXACTLY TWO THINGS**: the gait table hands `.waterfaring` an
  infinite limit — the toad and the fen lurker. The gate only refuses a step that goes DEEPER.
- **`pos.y` IS THE GROUND UNDER AN ACTOR**, written in ONE place (`game.groundActor`), EASED not snapped
  (`GROUND_RISE_RATE`/`GROUND_FALL_RATE`) — the camera rides the shoulder, so snapping kicks the frame. Past
  `GROUND_SNAP` it plants.
- **EVERY WORLD POINT ON AN ACTOR IS MEASURED FROM `pos.y`** — shoulder points, `centerWorld`, `lockPoint`,
  `topWorld`, crush points, dust.
- **THE CAMERA SHORTENS ITS BOOM RATHER THAN BURYING THE EYE** (`camera.followClear`).
- **BUT IT GIVES WAY TO TERRAIN ONLY, NEVER TO ITS OWN PITCH.** An up-tilt puts the eye LOW on purpose (that is
  `game.lockPitch` framing an ogre). Only ground standing PROUD of the hero's level (`GROUND_RISE`, just under
  one terrain riser) is worth paying distance for; on the flat the skim clamp lifts the eye those last few
  centimetres and the boom stays the player's.
- **THE HERO LEANS INTO THE HILL** (`hero.slopeLean`, 0.55 of the slope capped at 16°) through the SAME
  `rx(bodyPitch)` term as the run lean.
- **THE TERRAIN RECEIVES SHADOWS BUT DOES NOT CAST.** Self-shadowing a heightfield off a 108 m ortho box puts
  acne everywhere the surface grazes the sun.

### Performance — how a 560 m world stays cheap (`env.zig`)

- **UNIFORM GRID (CSR).** Props bucketed by 16 m cell into two indexes (structures, flora), built by counting
  sort into one flat array. Each cell carries the MAXIMA its pass needs, so a whole cell can be rejected first.
- **THE LIT PASS culls per cell then per prop** — four frustum side planes plus each kind's `view` distance.
- **THE DEPTH PASS culls by SHADOW REACH, not camera distance.** A caster throws its shadow `gfx.sunReach`
  times its height sideways — the cotangent of the sun's elevation, solved from the HOUR
  (`daynight.shadowReach`, written only by `Scene.setHour`). A prop matters iff its footprint plus that reach
  can touch the ortho box (`castsInto`).
- **COLLISION + ARROW FLIGHT query the grid**, never the whole solid list.
- **Check it, don't trust it.** Menu > Debug > Stats prints the live counts and `--shot` captures them. If
  `drawn` approaches `props`, a culler has been defeated. Caps are init-time PANICS
  (`MAX_PROPS`/`MAX_SOLIDS`/`MAX_SOLID_REFS`) — a silently dropped collider is a walk-through wall.
- **THE OCCLUDER FADE** (`env.markOccluders`): a prop between lens and hero goes thin, keyed to how much of him
  it hides. Three rules keep it from reading as a switch: the geometry sets a TARGET and an EASED ramp walks
  you there (`OCCL_IN` 0.16 s, `OCCL_OUT` 0.34 s — out is slower, and `easeShape` takes the speed off both
  ends); it stops being in the way over a BAND not a plane (`OCCL_DEPTH_BAND`); and `OCCL_MAX` counts what is
  in flight, both directions. The shape is a pure function of where the value SITS, never of where a travel
  began — `fadeTo` moves under it every frame the camera does.
- **EVERYTHING THINS EXCEPT WHAT SAYS `solid`** — architecture, cliffs, the water sheet, the bonfire. The flag
  is that way round because as an opt-in every kind added afterwards opted out by silence.
- **GROUND COVER THINS FROM HIS WAIST UP** (`OCCL_TALL` 1.15 m, the rig's SPINE at 0.640·H). `markOccluders`
  walks BOTH indices — `scanCell` over `stx` then `flx` — and the height gate is what keeps grass out of it.
  Coverage will not do that job: a tuft against the lens scores 0.54, over three times `OCCL_MIN`. **The gate
  is the INSTANCE'S height, `top * scale`, not the kind** — the scatter stamps 0.72..1.38. On the shipped map
  it passes 5,095 of 15,826: all cattails, thicket and ivy, most reeds, bush, grasstall, gorse and foxglove,
  and NOT ONE tuft, patch, fern, shrub, bracken, moss, clover, heather or mushroom. At his HIP (0.95) it let
  316 scaled patches and 303 ferns in.
- **AND IT COSTS NOTHING TO HAVE.** Flora is 15,826 of the map's 17,524 props; the gate leaves 45..52 reaching
  `thinFor` a frame beside the 22 the props index does. Measured over the whole map at 2.4/4.6/9.0 m of boom,
  what enlists is 0.11..0.15 instances a frame, worst spot 10, list peaking at 12 of `OCCL_MAX` 64 — against a
  lit pass issuing 865 draws and peaking near 1875. It was never a frame problem; it was shimmer.
- **A THINNED PLANT KEEPS ITS WIND** (`drawThinned`). `drawFlora` draws inside `Scene.setWind(true)` and this
  path is outside it. It goes on for BOTH of the pass's draws, never one: the depth prepass has to lay down the
  same geometry the colour pass draws, or LEQUAL throws the surface away.
- **THE OCCLUDER VOLUME IS NOT THE COLLIDER** (`props.Blocker`, `Info.occl`). A collider is sized for what you
  WALK INTO, an occluder for what you SEE THROUGH — a conifer's collider is a 0.58 m pole against boughs that
  block the view at 3.4 m. The trees carry cylinders off their own mesh builders (bole then crown; `y0`..`y1`
  off the foot). A kind with no `occl` falls back to the colliders plus `OCCL_SKIRT`, right where the two
  shapes agree — a pillar, and an ARCH, whose opening must stay see-through.
- **COVERAGE OPENS THE GATE, DEPTH SCALES THE ANSWER** (`thinOf`). `OCCL_MIN` is a coverage figure and nothing
  else. Multiplied together before the threshold, a mass a metre in front of him was discounted under it.
- **A THINNED OCCLUDER DRAWS LAST, AFTER EVERY OPAQUE THING, AND BACK TO FRONT** (`env.drawThinned`). It draws
  with the depth MASK OFF; left in cell order, the HERO came afterwards and composited at FULL opacity straight
  over it. Drawn last, the tree's alpha is what mattes HIM, so the reveal IS the ramp.
- **IT BLENDS ONE LAYER PER PIXEL.** A trunk stacks three or four surfaces along the ray and blended one after
  another the alpha COMPOUNDS. So each prop lays its own depth down first with the colour buffer held (`dst =
  0·src + 1·dst`, rlgl having no colour mask), and the pass after draws under rlgl's LEQUAL.
- **A FULL LIST GIVES ITS SLOTS TO WHAT HIDES HIM MOST — TAKEN OFF SOMETHING STILL SOLID** (`wantFade`).
  Nothing outside the list is ticked, so dropping an entry that has already left solid strands it thin or snaps
  it back; the victim is the least-thin ask among those still AT solid, and with none of those the ask waits a
  frame. A tree a frame late is not something the eye can see; a tree jumping back to solid is.

## Triggers, folk and dialog

StarCraft's trigger system on this world: CONDITIONS and ACTIONS; every condition must hold, then the action
list runs in order. `worldfmt.zig` holds the definitions as map data, `trigger.Runtime` everything that
changes, `dialog.Session` the one conversation that may be on screen, `npc.zig` the body you speak to. Nothing
about any of it is authored in Zig.

- **THE GENERAL-PURPOSE STATE IS WHAT MAKES IT COMPOSE**, not the condition vocabulary: named switches
  (`flag`), named integer counters, countdown timers. Without them every new bit of story state wants a new
  condition kind.
- **A NAME IS INTERNED TO A SLOT AT LOAD**, so a condition costs two bytes; the map carries the
  `flags:`/`counters:`/`timers:` tables so the file stays self-describing.
- **EVERY OTHER REFERENCE IS RESOLVED AFTER THE WHOLE FILE IS READ** (`link`) — a dialog may be declared below
  the trigger that opens it, and an `ask:` may point forward. An unresolved one is a LOAD ERROR.
- **EVALUATED EVERY FRAME, NOT ON A CYCLE.** A PRESERVED trigger is held off by `REPEAT_GUARD` (0.5 s) —
  without it `always` + `preserve` fires sixty times a second and never lets go of the screen.
- **A CONDITION IS LIVE, NEVER STICKY.** `region` is SC1's Bring exactly: true while he stands in it. Two
  conditions that come true at different moments are what the SWITCHES are for.
- **AN EMPTY `when:` LIST NEVER FIRES.** `always` is a condition you write down.
- **A `dialog` ACTION BLOCKS ITS OWN LIST AND NOTHING ELSE** (SC1's Transmission), and so does `wait`. Only one
  conversation may be up, and a trigger that wanted the screen is not advanced that frame — deferred, never
  dropped.
- **`deaths` IS MAINTAINED BY THE ENGINE**, off `justDied` through `eachTarget` — a latch (the sac's `killed`)
  would bill one death sixty times. The egg sac has no such edge, so the brood's own `bursts` bills it.
- **THE SCRIPT LAYER IS ARMED WHERE THE MAP CHANGES, NOT WHERE THE HERO DIES** (`game.armScript`): a load and
  every way out of the editor.
- **ONE BUTTON, ONE WRITTEN PRIORITY ORDER** — bonfire, then whoever is standing there, then a box
  (`game.interact`). The HUD prompt reads the same order.

### The dialog panel

- **IT IS SIZED TO WHAT IT HOLDS**, growing upward off a fixed bottom edge.
- **A GATE HIDES A LINE, IT DOES NOT GREY IT.** Nothing here has a `disabledMessage` to show, and a greyed row
  with no reason is worse than a row never offered.
- **YOU MAY NOT WALK OUT MID-SENTENCE.** No cancel — a conversation is left through one of its own endings,
  which is what lets `talked` mean "has heard this".
- **THE WORLD'S HUD GOES AWAY BEHIND IT**, as at a bonfire.
- **A NODE'S `act:` FIRES ON ARRIVAL AND A CHOICE'S `gets:` ON THE PICK**, both through
  `trigger.Runtime.apply`.

### The wanderer (`npc.zig`)

Not a foe: no `Vitals`, no `Leash`, no blade. Do not let the foe contract grow into it by accident.

- **A MAN STANDING STILL IS THE HARDEST THING TO ANIMATE.** THREE clocks at rates that never line up — breath,
  a weight shift, a head drift — so the loop never shows.
- **THE WEIGHT SHIFT IS A PELVIC LIST, NOT A SLIDE.** Translating the pelvis sideways carries both hips and
  `legChain` solves each leg straight down from its own hip, so both feet travel too. A roll about the pelvis
  raises one hip and drops the other.
- **AND ITS DROP IS PAID BACK AT THE PELVIS.** At rest this rig's leg is EXACTLY straight (pelvis 0.530·H,
  ankle 0.039·H, thigh + shank 0.491·H), so a pelvis a millimetre below rest puts the sole through the floor —
  there is no foot IK. Lift by `hx·sin(list)`.
- **NO PITCH AT ALL AT THE ROOT** — a root pitch rotates the LEGS, so one degree of stoop levers a planted foot
  half a centimetre into the ground. A stoop is thoracic anyway.
- **HE TURNS FIRST, THEN WALKS** (`TURN_GATE`). Stepping off before he is pointed at it makes travel disagree
  with facing, which IS a sidestep as far as the shared gait is concerned.
- **THE STAFF IS THE OTHER HALF OF THE GAIT.** A walking staff plants with the OPPOSITE foot, so the staff arm
  drives the pole down once a stride while the free arm swings at full amplitude.
- **WHERE IT POINTS IS AUTHORED IN THE WORLD, NOT IN THE WRIST** (`warrior.swingTilt`'s law). Built down the
  wrist's own −Y it inherits the entire arm chain: 46° off plumb at rest. The fit BILLS THE ARM for its
  abduction and pitch, leaving `STAFF_TILT` to mean degrees off plumb in the world.
- **THE BOOT IS THE HERO'S FOOTPRINT EXACTLY** — the gait curves plantarflex the ankle to a fixed angle at
  toe-off, so a longer toe is a longer lever below the plane and `legChain` can only level the ankle.
- **THE TWO HEAD VARIANTS ARE WHAT MAKES TWO OF THESE TWO PEOPLE** — hood up, hood back, picked by seed.
  Everything else varies through the POSE, which costs no mesh.
- **VALUE CONTRAST BETWEEN TWO LARGE AREAS CANNOT SURVIVE FULL DAYLIGHT ON THIS SUN.** A sunward face reads
  `255·(albedo·1.72/255)^(1/2.2)`, so albedo 40 comes back at 142 and 58 at 168. Layer on HUE, which the sun
  does not flatten, and spend value contrast only where the area is small (`LINEN`) or is a hole (`HOOD_IN`).

## Sight and leashing

**A LOOK IS A SEGMENT AND IT IS TESTED EXACTLY** (`collision.blocksSight`) — one segment-vs-capsule test per
solid, never a walk of samples. It passes OVER anything whose blocking height is under both ends.

**THE GRID IS WALKED, NOT COPIED** (`env.sees`) — `nearSolids` truncates at `MAX_NEAR`, which over a 20 m line
through a wood quietly drops the wall it was asked about.

**IT IS ASKED ONCE A FRAME, BY THE GAME** (`game.markSight`) for every foe inside `SIGHT_R`, stamped on that
foe's `Leash`. Creatures do not ask it themselves — the prop grid belongs to `env`.

**WHAT IT LOSES IS ITS EYES, NOT ITS MEMORY.** `Leash.blind()` needs `SIGHT_MEMORY` (6 s) with no line, longer
than `LEASH_CALM`, so breaking sight can never shed a foe faster than walking away does. **A blow outranks
blindness** — `roused()` beats `blind()`.

The leash is one struct every creature embeds:

- **START FAR, STOP NEAR** — turns for home past `foe.leashR(AGGRO_R)`, stops inside `LEASH_HOME_R` (3 m). That
  gap IS the debounce.
- **THE TETHER IS THE CREATURE'S OWN NOTICE RING PLUS `LEASH_SLACK` (6 m)**, not one authored number. A flat
  30 m was also THE SPACING BETWEEN CAMPS, so a tether reached the next encounter.
- **ONLY AFTER `LEASH_CALM` (4.5 s) WITH NO BLOW GIVEN OR TAKEN**, and only once the hero has left the patch.
- **THE PATCH IS A PLACE, NOT A SEPARATION** — both ranges in `Leash.tick` are measured FROM THE POST: how far
  the CREATURE has come, and how far the HERO is. Asked as the gap between the two BODIES, tethers nominally
  17–30 m long measured out at 34 m (ogre) to 176 m (leechfly). A test walks the field and pins each one
  (`game.zig`, "NOTHING CHASES FOREVER").
- **A WALK HOME IS NOT BLIND** — step back into the patch, or land one blow, and it turns on the spot.
- **A FIGHT IN PROGRESS OUTRANKS THE TETHER, and that is not a leak**: `noteCombat` is stamped by every blow
  either side lands, so a leechfly that rides him for eighty metres has been FEEDING the whole way. What a
  tether owes there is a prompt let-go once the biting stops — a CLOCK, not a distance.
- **RE-ENGAGING COSTS `REENGAGE_HOLD` (8 s)** in which it cannot try to leave again.
- **ONE PLAYER BLOW ROUSES IT FROM ANY RANGE for `PROVOKE_ROUSE` (14 s)** — a COUNTDOWN, not a level, because
  it has to outlast the walk. Only a `pierce` blade also snaps its facing back down the shaft.
- **KEEP AT IT AND THE LEASH BREAKS** (`PROVOKE_BREAK`, held `PROVOKE_HOLD`). The anti-cheese. Not gated on
  `pierce`, or the sword is exempt.
- **IT REACHES EVERY STATE MACHINE BY BENDING THE SENSED RANGE** (`foe.sensedDist`), not by bolting a second
  decision tree onto each. Only the DECISION sees the bent number. **Every decision, including the ones after a
  leap** — the kobold's dash and the archer's backstep both re-decided on the raw distance when they landed.

**Foe pacing:** the archer's BACKSTEP is a committed jump straight back, inside sword reach, on a 7 s cooldown
— it buys the shot back exactly once. An evade you can spam is a wall.

**A TELEPORT IS A JUMP, AND THE ROOTS REFUSE IT** (`shade.wantsBlink` → `foe.canLeap`), gated where the move is
CHOSEN. It is also the one move that must not fire out of a STAGGER: a creature that vanishes mid-flinch erases
the punish window, so the blow sets a latch (`spooked`) and the blink is spent at the next choose site. Half a
blink is `airborne()`, which is what exempts the jump from `game.gateTerrain`.

**A MOVE THAT CANNOT LAND IS NOT A DECISION.** The ogre's swipe passes clean OUTSIDE anything hugging its legs
(`swipeInner` 2.28 m) and collision holds the hero at 1.68, so toe to toe `classify` was spending two thirds of
a second on a guaranteed miss. A choose site tests the move's OWN band, not just its outer range.

## Saving, and the boot screen (`save.zig`, `menu.zig`)

**YOU SAVE AT BONFIRES AND NOWHERE ELSE.** No Save row anywhere; sitting down IS the save,
`game.tickRest`'s `justEntered` is the one line that writes one, and it lands in whatever slot is being played
(`g.slot`) without asking. **THREE SLOTS**, `save1.dat`…`save3.dat`, each with a `save<n>.png` beside it.

- **THE FILE IS TEXT IN THE MAP'S OWN GRAMMAR** (`key: value`, `version:` first). Unknown key, bad version or
  another map's name are LOAD ERRORS — a save is refused whole rather than applied in half.
- **THE FIRE HE SAT AT IS WHERE HE COMES BACK, AND SO IS THE ONE HE LOADED AT.** `tickRest`'s `justEntered`
  stamps `hero.setSpawn` at the SEAT for the live session, and `save.scatter` takes the checkpoint off `at:` —
  the position IN THE FILE — because every write in the game is inside the rest flow, so a save's position IS a
  bonfire seat and a second stored point can only ever be the stale one. The file's `spawn:` row is READ AND
  DROPPED and the key may never leave the parser: an unknown key is a refused save and every file on disk has
  that row. `enterMap` still stamps the entry, so a new map is its own checkpoint until he next sits down.
- **THE BARS ARE NOT IN THE FILE, AND THAT IS THE POINT.** `hero.sit` runs `makeWhole` before the write. The
  SHEET is out for the same reason: it is `ptree.Bonus.sheet()` of the tree below, and `game.applyTree`
  re-derives it on the way back in.
- **IT IS GATHERED AND SCATTERED THROUGH ONE VIEW** (`save.Slot`, `game.slotOf`): the save file owns no game
  state and reaches for nothing. Parsing goes into a `save.Data` on the stack FIRST and is committed only if the
  whole file read.
- **A LOAD LANDS IN A FRESH WORLD AND THEN OVERWRITES IT** (`game.loadGame`). Every array the file does not
  mention is at what a NEW game has. The order is load-bearing: `beginGame` sizes `chests.n` off the map and
  rebuilds the trigger ORDER, both of which the file writes into and neither of which it carries.
- **`beginGame` IS THE ONE ANSWER TO "WHAT IS A FRESH GAME"** — `Game.init` and New Game both come through it.
- **A DEV RUN WRITES `devsave<n>`, NEVER THE PLAYED SHELF** (`save.useDevShelf`, set once in `game.run`).
  `--map` and `--shot` used the same three filenames: one rest at a test map's bonfire overwrote `save1.dat`,
  and since the file then named a map the shipping boot cannot match, the picker showed that slot EMPTY and
  New Game finished the character off. `--shot` clobbered `save1.png` the same way. Every reader and writer in
  `save.zig` goes through `path`/`shotPath`; nothing indexes the name arrays.
- **THE THUMBNAIL IS A POST-DRAW GATE, NOT A DECISION AT THE EDGE** (`game.takeSlotShot`). `justEntered` fires
  at the BOTTOM of the fade-in where the screen is black, so what is OWED and when it can be PAID are different
  frames. Taken after the world is drawn and before the HUD and the fire's list go over it. The harness calls
  the same function at the same point (`shots.bonfireShoot`) — `--shot` never runs the loop, so that is the only
  thing proving the grab works.

**THE BOOT SCREEN IS ITS OWN SCREEN, not the pause card with different rows.** New Game / Load Game / Options /
Editor / Quit, over a live 3D backdrop the camera walks slowly round (`game.BOOT_*`).

- **IT HAS NO BACK AND NO CONTINUE**, and Select/Start are refused while it is up (`Menu.booting`) rather than
  gated at each call site. **QUIT IS ITS ROW**; from inside a game the way out is `Back to Title`.
- **`menu.home` IS WHICH ROOT A SUB-SCREEN RETURNS TO.** Options hangs off both cards, so a hard `.main` dropped
  you into the pause menu of a game nobody had started.
- **THE BOOT CAMERA IS ASKED FOR AFTER `menu.update`, NEVER BEFORE.** `dist`/`pitch` are the PLAYER's zoom and
  tilt and nothing in play resets them, so stamping the title framing on the frame New Game was pressed handed
  the new character a camera seven metres back.
- **BOTH ROWS ASK WHICH SLOT.** Three slots is few enough that choosing is the point of having them.
- **A SLOT CAN BE THROWN AWAY, AND IT IS THE ONLY PRESS IN THE GAME THAT DESTROYS ANYTHING** — armed on one
  button (`hud.BTN_QUICK`) and done on a SECOND, the ordinary Confirm, because by then the row has become the
  question. Walking off the row, Back, or re-opening the picker all disarm it. **BOTH FILES GO** (`save.erase`).
  The menu holds no game state, so it hands `Action.deleteSlot` up and `game.zig` does the removing, the
  re-survey and the re-read of the pictures.
- **A ROW THAT CANNOT BE PRESSED IS DRAWN SO** (`Menu.rowLive` + `Card.dim`, `TEXT_OFF`) — one predicate read
  by the PRESS and by the picture. The cursor still lands on it: the reason is the footnote.
- **THE PICKER'S THREE TEXTURES LIVE NO LONGER THAN THE PICKER** (`menu.loadShots`/`unloadShots`).
- **ASCII ONLY, like every string in the game** — the atlas has no em dash and one renders as tofu.

## Controls (`game.zig`)

Keyboard+mouse or gamepad; the pad follows **Elden Ring's default layout** (ER is the north star throughout).

**WALK vs RUN:** the whole left-stick range is WALK (tilt scales walk speed only), and RUN is exclusively the
hold-B / hold-Shift sprint. Gate run-only flourishes on `sprintB`, not the stick-speed `runB`.

- **Mouse:** hidden over the window and drives the camera, but NEVER locked/captured. Do NOT reintroduce
  `disableCursor`/pointer-lock.
- **Committed actions with an ER-style input queue** — an attack/roll pressed mid-action buffers in ONE slot
  (last press wins; a same-frame roll outranks attack) and fires at the earliest exit. A queued roll leaves in
  the direction HELD at fire time, not pressed.
- **INTERACT IS Y, EVERYWHERE** — `game.INTERACT_PAD`/`INTERACT_KEY`, and the keyboard mirrors the pad letter
  for letter so no crib ever has to name a key. It is the one face button ER leaves free: A is the jump, B the
  roll, X the quick item. The dialog panel takes it on top of the menu Confirm. The quiver's keyboard cycle
  moved off Y to `ARROW_KEY`.
- **Guard or CAST:** hold L1/LB or RMB. The button belongs to the HAND, not the shield.
- **Aim or PARRY:** L2 is that same hand's SKILL slot — a raised bow aims on the HELD level (or RMB with the bow
  out), boards parry on the PRESSED edge (`PARRY_KEY`).
- **THE RIG TILTS ONTO WHAT IT IS LOCKED TO** (`game.lockPitch`). The boom's pitch IS the view's, so the right
  number is the angle from the EYE down to the mark. Measured off the LIVE eye rather than solved, which makes
  it a convergent feedback loop (gain `boom / (boom + range)`) that `camera.aim`'s ease damps. It is why
  `camera.PITCH_MIN` is −0.38.
  **THE TILT UP IS EARNED BY HEIGHT *AND* BY CLOSENESS**, and it is a SHARE rather than a switch
  (`lockTiltShare`, the product of two smoothsteps, so neither gate can step). **DOWN IS FREE; UP IS EARNED**
  (`LOCK_TILT_TALL`): the up half is gated on how far the creature reaches into the sky OFF ITS OWN FEET
  (`topWorld`), which keeps a kobold standing on a rise a kobold. Only the ogre and the Rooted clear it
  standing, and the LEECHFLY clears it once it has climbed.
- **Lock-on:** R3 / middle mouse; a flick cycles. Suspended entirely while aiming. Two ER exceptions: a hold-B
  sprint faces TRAVEL, and an attack's recovery tail re-squares (`ATK_RETRACK`). **YOU CANNOT FIX ON WHAT YOU
  CANNOT SEE** — a foe behind a wall is not offered (`game.canSee`), but a HELD lock fades rather than switching
  (`LOCK_BLIND_HOLD` 1.1 s).
- **Cross/A = JUMP** (keyboard `V`). Not a clash with the menu Confirm: every screen that takes Confirm holds
  the world still. `hud.BTN_JUMP` is named apart from `BTN_CONFIRM` because a rebind of one is not a rebind of
  the other.

## Hard invariants & gotchas

- **Coordinates:** ground is XZ, Y up. Hero faces +Z at yaw 0; `atan2(facing.x, facing.z)` is the facing angle.
- **Strafe sign:** the camera looks +Z from behind, so screen-right is world −X → `camera.rightXZ` MUST be
  `(−cos yaw, 0, sin yaw)`. Flipping it mirrors L/R walking.
- **VSYNC, not `setTargetFPS`.** `vsync_hint` before `initWindow`, no frame cap — `setTargetFPS` is a CPU-side
  limiter that never asks the driver to swap during vblank, so the swap TEARS in exclusive fullscreen, and two
  limiters fight on any panel that isn't 60 Hz.
- **Depth z-fighting:** `rlSetClipPlanes(CLIP_NEAR, CLIP_FAR)` (0.55, 320) at startup. The ground sits a hair
  above y=0 (`env.GROUND_Y = 0.01`) so content is planted-to-slightly-embedded and never FLOATS.
- **Sun + shadows are STILL ONE source** — `gfx.sun`, solved from the hour (`daynight.keyDir`), written only by
  `gfx.Scene.setHour`, feeding the shader, the shadow camera and `env`'s depth cull. `gfx.SUN_DIR` is the ANCHOR
  the cycle is solved through, not what casts.
- **Shadow pass contract:** every caster draws through `game.drawCasters` (both passes, so transforms can't
  drift). drawMesh/drawModel use the MATERIAL's shader, so the depth pass swaps caster shaders
  (`setCasterShaders`) and runs BEFORE `beginDrawing`. Terrain and FLORA receive but do not cast. The ortho box
  tracks the hero, snapped to shadow texels, and tracks Y as well.
- **The hero is per-bone matrices, not `drawModelEx`.**
- **The scene shader gammas output (`pow 1/2.2`): author dark colours near-black.**
- **Vertex alpha is the EMISSIVE channel** (255 = fully lit; lower = self-lit).
- **…AND MATTER WANTS 248+, NOT 206.** `lit = mix(lit, base*1.35, 1 - a)`, so an alpha of 206 puts 0.19 of the
  raw albedo on everything unlit. In SUN that is a 6% lift (nothing); in SHADOW it is a floor the terminator
  cannot get under, and a whole creature authored at 206 reads as one flat lump however well its albedo is
  solved. Reserve the low alphas for the things that are LIGHT (a throat, a flame, an eye).
- **A BIG SMOOTH MASS NEEDS A NEARLY-BLACK ALBEDO — and FORM BREAKS.** The hot key (×1.72) plus the gamma lift
  turns any mid-dark value pale on a large sunward face. The bigger the face, the darker it must start.
- **TWO STONE MATERIALS.** `.stone` is rubble masonry, matte; `.marble` is dressed stone, veined, with the only
  real gloss besides steel and water — kept LOW. Marble = columns/arches/statues; stone = walls/towers/rubble.
- **`gfx.Mat` is APPEND-ONLY** — the shader branches on the raw ordinal from 1 to 16, and the comptime asserts
  pin the TAIL (water 9 through gilt 16). Pinning `water == 9` is what catches an insert below it. **The
  VERTEX-ANIMATED ids are bounded at BOTH ends** (`> 11.5 && < 13.5`, and fog's `> 14.5 && < 15.5`): an
  open-ended test claims every id added after it, which is how `bark` went in and every trunk started climbing
  like an ember.
- **THE FLAME MATERIAL IS THE ONE THING DRAWN SEMI-TRANSPARENT BY ITS MATERIAL** (the faded hero under an aim is
  the one drawn so by a per-draw uniform). Opacity is graded off the emissive (`FLAME_A_CORE`→`FLAME_A_TIP`);
  depth WRITE stays on so tongues don't stack into a brighter core.
- **THE FOG GATE IS A VEIL** (`props.foggate`, `propfx.fogGateMesh`, `Mat.fog`). Laid down in `env.drawVeils`
  AFTER everything opaque, because its own depth write at the head of the sheet is a rectangle of missing world
  behind it. `build` is the two threshold stones and the sheet is the veil; `solid` is TRUE.
- **ITS HEIGHT FRACTION RIDES `animY` AND IS READ TWICE** — the vertex billow in the VS and the fade in the FS.
  It has to INTERPOLATE across a cell (`gfx.Builder.quadFadeAnim`): constant per cell it steps. **And the height
  the fade dies at WANDERS** (per world column, over time) — a few percent of alpha over something this bright
  is still a straight edge.
- **ITS VERTEX ALPHA IS LEFT NEAR-SOLID ON PURPOSE.** The scene shader reads `1 - fragColor.a` as EMISSIVE, so
  fading a translucent thing through the vertex colour makes it GLOW as it goes.
- **BUILDER WINDING IS NOT CHECKED, AND FACE-DOWN GEOMETRY IS INVISIBLE.** A flat annulus swept outward-first
  points DOWN and raylib culls it. Sweep inner@a0 → inner@a1 → outer@a1 → outer@a0. For a ring, radial is the
  position direction and tangent is `(cos a, 0, sin a)`; for an arch ring at angle a, radial is `(−cos a, sin a,
  0)`, tangent `(sin a, cos a, 0)`. `addBox` also accepts a NON-PERPENDICULAR axis triple and builds a skewed
  parallelepiped.
- **A CURVED SHAFT DRAWS ITS CURL ONCE AND APPLIES IT EVERY SEGMENT.** Re-rolled per segment it wanders, and a
  wander made of straight capsules is a chain of elbows. Total arc is per-segment curl TIMES segment count, so
  moving either the length or the count re-brackets the curl.
- **A MOTE IS A CAMERA-FACING TEXTURED BILLBOARD, NEVER A SOLID SPHERE** (`foe.drawParticles`, `foe.setLens`).
  A hard-edged Lambert ball reads as a flat circle; a quad through a radial-gradient sprite has the soft falloff
  every real particle kit is built on, and at 4 vertices costs a tenth of the sphere. Two sprites, lazily built
  on first draw: SOFT is the glow (light, smoke, stains), GRAIN keeps a near-solid core for matter in flight
  (blood, chips, clods). Two passes per pool — alpha MATTER first, then additive LIGHT — depth TESTED, never
  WRITTEN.
- **A POOL NOBODY CAN SEE MAY NOT BE DRAWN** (`foe.motesVisible`) — not for the per-mote cost but for the COUNT:
  twelve chaos clouds at 132 motes each still walk their whole array. The gate is a REACH and a HEMISPHERE and
  **it is not the frustum and may never become one** — `env.View` is the frustum, there is one of them, and a
  second culler is the empty-world bug. A pool the lens is standing INSIDE always draws.
  - **AND IT IS NOT GATED ON THE EMITTER BEING ALIVE.** A cloud ticks its motes past its own death, so a puff
    laid on the last frame still fades out; `shroom`'s own test pins that.
- **A RING THAT OVERWRITES ITS OLDEST DOES IT SILENTLY**, so its size is arithmetic over what feeds it (every
  emitter's worst frame), asserted at comptime — never a round number that looked big enough.
- **A cylinder is CAPLESS** — an open end shows its culled interior. Cap with `addDome` or an axis-flattened
  `addBlob`; a flat cap constrains the piece to a world axis.
- **REPEATED BIG PROPS NEED VARIANTS.** One mesh placed sixty times reads as a periodic pattern; yaw and scale
  do not hide it. The three `bigtree` kinds and six `cliff` kinds exist for this, drawn through an op's weighted
  `mix=`. Long-wavelength variation beats per-instance noise.
- **A CULLER BUG LOOKS LIKE AN EMPTY WORLD, AND ONE-ORIENTATION TESTS MISS IT.** `View.fromCamera`
  sign-corrects its plane normals against the camera forward rather than assuming a handedness. Its test sweeps
  seven headings.
- **A LIGHT'S RADIUS MATTERS MORE THAN ITS BRIGHTNESS.** A 9 m torch in a 5×7 m chapel reaches every surface
  from every corner, so four summed to a flat wash however dim each was. Fire has to POOL.
- **Fullscreen shader passes must build ray/UV from `gl_FragCoord`** + a resolution uniform when drawn via
  `drawRectangle` — raylib maps rectangle texcoords to the tiny shapes-texture rect, so `fragTexCoord` is
  effectively CONSTANT. `drawTexturePro` blits are fine.
- **Retro pass contract:** with any filter active the frame renders into `Retro.rt` then blits through the
  combined shader; vignette, HUD and menu draw AFTER the blit. All-zero = bypassed entirely.
- **THE RETRO RT IS `GL_NEAREST`, AND PIXELATE POINT-SAMPLES IT.** `sceneTap` box-filters the block (`PIX_BOX`)
  instead of keeping one pixel of four, which is a TRADE — the twinkle IS a hard edge crossing a pixel boundary.
  **Sub-pixel filter offsets snap under nearest**, so the chroma fringe's offset snaps to whole BLOCKS.
- **THE UI NAMES BUTTONS, NEVER KEYS.** Every prompt, crib and footer in the GAME shows the button that does the
  thing, DRAWN — `hud.Hint`, `hud.hintRow`/`hintRowAt`, and the `padFace`/`padDpad`/`padBumper`/`padMenu`
  pictograms ported from zig-diablo's `hudx`. No keyboard caption anywhere and no pad-vs-keyboard branch: one
  strip, whether a pad is plugged in or not. Keys still work. The glyphs live in `hud.zig` and not `uiart.zig`
  because a face button is a LETTER, and that file is the only path to draw text. **The EDITOR is the one
  exception** — a mouse-and-keyboard authoring tool with no pad bindings, so its crib names keys.
- **A BUTTON IS NAMED ONCE** — `hud.BTN_INTERACT`/`BTN_CONFIRM`/`BTN_BACK`/`BTN_QUICK`. `game.zig` binds off
  them and every crib draws off them, so a rebind moves the caption and the press together.
- **THE CURSOR IS A LEADING BAR, AND IT IS THE ONLY THING THAT MARKS A ROW.** `uiart.caret` draws it and
  `uiart.rowHilite` lays it under the wash, so a list cannot grow a second kind of cursor. A row too dim to take
  a wash draws the bar on its own at `CARET_DIM`: the cursor may never be invisible on the row it is standing
  on. The `<` `>` PAIR ON A GAUGE stays — that is "this row adjusts", not "you are here".
- **All UI text goes through `hud.text/textW`**, in **Balthazar** (`assets/`, OFL). The atlas is ASCII-ONLY — a
  `·` or `—` renders as tofu. One face only.
- **SIZES COME FROM `hud`'s TYPE SCALE** (`TITLE`/`BODY`/`SMALL`/`HINT`/`TINY`, plus `MONO` for the editor),
  never a literal at the call site; rows step by `hud.lineH(size)`. The atlas resolution must stay ABOVE the
  largest size drawn, and the drop shadow's offset scales with the size.
- **HUD colours are LITERAL screen values** — drawn after the retro blit, outside the scene shader.
- **THE CHROME FADES AS ONE PICTURE, NOT AS A LIST OF THINGS THAT EACH KNOW AN ALPHA**
  (`hud.beginChrome`/`endChrome`, `game.HUD_FADE_DUR` 0.55 s, read off `hero.deathT` — the clock the YOU DIED
  card is drawn from, and short of the card's own first beat). Composited through a target because the
  alternative is threading a factor through every literal in `hud.zig` PLUS `uiart`'s rules and the `itemart`
  pictures. The target is only taken WHILE a fade runs — at full chrome `beginChrome` refuses. **The BANNER is
  not chrome** and is laid down after `endChrome`.
- **Prototype models/meshes are permanent** (CPU arrays stay attached and leak at exit — fine). Don't
  `unloadModel` them. TERRAIN TILES are the one exception, and cost two crashes:
  - **`gfx`'s mesh allocator MUST be `raw_c_allocator`, not `c_allocator`.** raylib frees mesh CPU arrays with
    libc `free()`, and `std.heap.c_allocator` does not hand out malloc pointers on Windows — freeing one frees
    an interior pointer. Heap corruption, surfacing as `0xC0000374` with no stack.
  - **A MODEL'S MATERIAL CARRIES THE SCENE SHADER, AND ONLY THE PINNED raylib SPARES IT.** Go through
    `env.unloadTerrain`, which points the material at raylib's default shader id first. The bundled raylib 5.5
    `UnloadModel` frees `materials[i].maps` and never calls `UnloadMaterial`, so today the swap is belt to the
    braces — but `UnloadMaterial` unloads any shader that is not the default one, and a raylib that routed
    through it took the scene shader out from under the whole frame.
- **AND `env.build` MAY RUN ONCE PER PROCESS** (`envBuilt` panics on the second). It makes every prototype, the
  ground and the water sheet and clears `tileBuilt`, so a second run strands all of it.
- **GLSL RESERVED WORDS ARE NOT ONLY THE OBVIOUS ONES.** A local named `patch` compiled everywhere the author
  tested and failed on Intel, which enforces it at `#version 330`. `layout`, `subroutine` and friends are the
  same trap, and a scene shader that fails to compile is a hard startup panic.
- **raylib's `SetSoundPan` IS THE LEFT CHANNEL'S GAIN, not a position.** The mixer is `left = pan; right = 1 -
  pan`, so **`pan = 1.0` is hard LEFT**. `audio.panFor` is the only place the sign is decided and a test pins
  it. The pan law is `0.5·x·(3 − x²)`, so a hard-panned sound is ~3.2 dB louder in its own ear than a centred
  one.
- **`master` NORMALIZES each voice** (`norm`), so a layer's `amp` sets its BALANCE inside the voice and only
  `BANK.gain` sets how loud it is. **THE FIGHT IS ONE BAND** — combat rows above `BATTLE_FLOOR` (0.34) are
  pulled geometrically toward the soft end, halving the spread in dB. Retune by moving the FLOOR, not by pushing
  one row back up; a test pins the ratio and the orderings.
- **THE VOLUME IS RESERVED FOR WHAT IS ABOUT TO HIT YOU.** A creature's committed arrival outranks its own
  movement noise — lunge over hop, slam over step, stab over wingbeat, swing over creak — and the tells sit past
  the midpoint of the band. **TEXTURE GOES AT OR UNDER THE FLOOR**, which takes it out of the band entirely:
  hops, the wingbeat, the idle creak, the whirl. A second test pins both halves, in PAIRS.
- **TEXTURE IS THINNED IN COUNT, NOT JUST IN LEVEL** — `leechfly.DRINK_EVERY`, `rooted.CREAK_EVERY`, and the
  hiss the brood mother no longer spends on laying a sac. The one cadence that MAY NOT be thinned is
  `leechfly.WHINE_EVERY`.
- **THE FAMILY LEVEL IS `TRIM_COMBAT` (0.46), NOT THE FLOOR** — the floor moves only the `battle()` band, where
  the trim reaches the literal-gain rows too. **And the fight is rolled off the top** (`COMBAT_TREBLE`, one pole
  at bake in `bakeTake`, UNDER the player's rack so a dial still sits on top of it).
- **The sound filter rack is BAKE-TIME** — raylib cannot filter a playing voice, but every voice is
  synthesized, so a dial re-renders that family (coalesced by `FX_SETTLE`). A bake STOPS every take before
  freeing any of it. **IT LIVES IN THE EDITOR, beside the JUKEBOX** (`editor.rackPanel`, the `.jukebox` modal):
  it is an authoring tool rather than a setting. Its eleven dials end in the EQ pair (`AF_BASS`,
  `AF_PRESENCE`), applied LAST. The RETRO rack stays in the menu; that one is a LOOK the player picks.
- **AND THE BENCH EDITS ONE VOICE, NOT JUST A FAMILY.** `BANK` is the ORIGINAL and never moves; `live` is the
  copy every play path reads and the only thing the editor writes, so **revert is free and cannot be lost**.
  `settings.cfg` carries the DIFFERENCE only, one `voice.<name>` line per edited voice. Five dials (`Dial`: vol,
  pitch, reach, and the two jitters) answer under the finger; the eleven filters are bake-time and ride the same
  `FX_SETTLE`, applied ON TOP of the family's. **`vars` and `poly` are NOT on the bench**: they size the alias
  table `freeRow` walks to unload a row, so a dial that moved either between a bake and its free would leak or
  double-free — they, `mix`, `id` and `make` are read from `BANK` everywhere and have no setter. A test pins all
  four against `live` for every voice.
- **Never bulk-edit source through PowerShell** `Get-Content`/`Set-Content`: em dashes mojibake and a BOM
  appears. Use the Edit tool.

## Gaps

- **Bone Knight:** no fighting stance. `poseUpper` sets no leg pose while standing, so `legChain` gives him
  straight legs and rest-offset feet — no knee flex, no foot stagger, no weight on the back foot, through
  either stroke. `legBrace` only drops the pelvis. It cannot be bolted on AFTER `legChain` (that is the hand
  that levels the ankle), and a bespoke walk is forbidden, so the stance has to go THROUGH `legChain` — every
  creature's change, not his. No RIPOSTE behind the parry. His arena is authored by HAND in the `.world` file;
  there is no arena brush and no way to say "these props are a room".
- **Necromancer:** no `necro_*` voice family (borrows the shade's, the wand's and the skeletons'). Nothing
  raises a BODY but this creature, so `foe.rekindle` still has two callers — the ancient priest claws a new
  skitterer out of the ground rather than reanimating anything, and it is the second COLD source.
- **Combat:** no criticals, no guard counter, no AR × motion-value damage (flat constants). Nothing scales a
  cast. Fifteen creatures carry parry windows now; what carries none says why at its own impact site
  (projectiles, ground discs, poured elements — broodlings out on purpose).
- **The jump exists but nothing hangs off it** — no jump ATTACK, no fall damage at any height, and no creature's
  move misses him for being over it (a per-move height would be authored at each `toImpact` the way a parry
  window is).
- **Souls buy levels and nothing else** — the caravaneer is a body on the road, not a shop; nothing in the game
  buys or sells. The PASSIVE TREE is 81 nodes with no respec, no jewel sockets, no second grant on a node. Every
  attribute is raised by at least one node (test-pinned) and NO attribute is inert; `stats.inert` stays and
  answers false for all seven, because the next attribute arrives dead the way LUCK did.
- **TEN METERS NOW, AND EACH SAYS WHO CAN CARRY IT** (`combat.Ail`, `combat.AILS`) — poison, burning, chill,
  stun, bleed, sleep, confusion, charm, berserk, stupefy. A full meter reaches the state machine: stun and sleep
  come out of `foe.grip` as `downed`, chill and stupefy take the FEET, charm and confusion re-point
  `foe.Threat`. **WHAT IS STILL MISSING IS A PANEL** — `combat.ailSays` writes one line of mechanic per row and
  nothing calls it, so the meters explain themselves nowhere but in `item.effect`'s own sentence.
- **Equipment:** every registered piece is live and the SWORD HAND draws what is in it (`hero.Blade`/`bladeOf`,
  three shapes on one bone) — but the **WARBOW and the DOOR are still the plain bow and the small shield**. The
  door has a mesh to borrow (`knight`'s bowed wall); the warbow is the bow at another scale. **NOTHING WORN
  SHOWS ON HIS BODY AT ALL** — helm, coat, belt, boots and both rings are a number, a bag picture and a socket
  caption. Every doll socket has at least one piece for it now (helm 3, neck 2, belt 1, feet 2, ring 4,
  ring2 2). The crock lands with no burst FX; the tallowed blade shows nothing on the sword.
- **Rig:** no foot IK — `rx(bodyPitch)` rotates about the WORLD ORIGIN, so a deep lean levers a forward-swung
  foot down and feet clip a few cm on slopes. The roll has front-loaded i-frames but no collision. One leg-cycle
  is reused across run and sprint.
- **Elevation exists but nothing is authored with it:** no falling, terrain casts no shadows, painted water is
  one level plane.
- **The script layer is foundations only. THE EDITOR CANNOT AUTHOR THE SCRIPT** — no Triggers layer; triggers
  and dialogs are hand-written and the editor round-trips them untouched because the writer emits them off the
  same tables. NPCs it does place: the unit brush is the foe kinds, then the npc kinds, then an eraser (pinned
  at comptime in `editor.zig`), and `dlg=` on a placed npc is still text. Two `NpcKind` (`wanderer`,
  `merchant`). No quest log, no journal. A roamer wanders inside a radius about its post; no authored patrol
  points. `deaths brood_sac` is billed off the brood's own `bursts`.
- **Three editor holes, all fields the FORMAT has and the panels do not.** `Op.r1` on an `at` is how far off the
  ground that prop is lifted (`env.Placer.expand`) and no panel exposes it. `Op.field` thins a scatter by the
  ground-cover noise (`env.accepts`) and is ON by default for a `belt`, with no control either way. And **NO MAP
  CAN SAY WHERE THE PLAYER STARTS**: `game.beginGame` plants him at (0, 4) facing south in every world, which is
  why a test map has to be built around that spot. Everything else the writer emits has a panel, plus
  undo/redo, cut/copy/paste and grid snap.
