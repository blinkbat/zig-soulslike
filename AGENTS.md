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
- **AN ERROR LOOP DOES NOT NEED A BINARY** — `check.cmd` (`zig build check`) type-checks the exe root AND
  the test root and stops: 2.7 s against the 10 s a build costs, because sema is 1.4 s of a build and LLVM
  plus LLD are the other 7. Use it for every edit until it is clean, then build once.
- Verify rendering/animation by RUNNING `zig-out\bin\zig-soulslike.exe --shot` (or `shot.cmd`) and inspecting
  `shots\` (gitignored). Never claim a visual change works without a shot.
- Do NOT launch the interactive window to "check" — the owner plays it himself, and while he has it open the
  build cannot overwrite the exe. Build with `--prefix zig-out-dev` when locked.
- `--shot-props` renders every kind alone into `shots\props\`. For ONE model the editor's object viewer is
  faster.
- `--shot-art` lays the whole 2D set on contact sheets in `shots\art\`: every editor glyph at its 18 px and
  at 3x, every item picture at the 34 px bag cell and a plate, the spells, the ailments and the pad kit. A glyph
  set is judged as a SET, and this is the only frame that shows one.
- **AN EYE PASS IS A LOOP, SO SHOOT ONE STAGE** — `--shot --shot-only <substr>` (`shots.onlyStage`) runs the
  named stage and skips every other frame's render and write: 32 s against 3m38s for the lot. A filtered run
  still SIMULATES everything, so nothing a later stage stands on goes unbuilt.
- **AND WHEN THE THING PHOTOGRAPHED IS HOW A BODY HOLDS SOMETHING, SHOOT ALL FOUR SIDES CLOSE**
  (`shots.knightDoorShots`). The house three-quarter portrait at 12 m answers nothing: the door covered the
  whole creature and the arm behind it was four grey pixels. Turn the SUBJECT rather than orbiting the lens,
  so the sun stays over the camera's shoulder, and solve the boom off what is actually being held — a plank
  that stands forward of him is NEARER the lens than his crown and overflows a boom solved off that.
- **Framing is part of the test.** Confirm the camera SHOWS the moving part before tuning. `follow` does not
  clamp pitch, so a small negative pitch at long `dist` puts the camera under the terrain; the camera ends at
  `target + back*dist`, so interior framings must be DERIVED from the room's extent; the shadow ortho box
  tracks the HERO, so `standHero` near your subject. For a world change take a steep overhead (`dist` ~55).
- **A FRAMING THAT HAS TO SURVIVE A RE-AUTHORED MOVE IS SOLVED AND PINNED, NOT PICKED** (`shots.KNIGHT_STRIP`,
  `STRIP_FILL`, and the test beside them). Boom off the SWEPT BOX of everything the move moves — kit, the other
  hand's kit, and the body under them — aim at that box's middle, and let a test re-measure and re-solve. Framed
  for the old arcs at 13–15 m the knight's four strokes filled 40% of a frame aimed a metre over the action;
  `camera.FOVY` and `game.SCREEN_W`/`SCREEN_H` are public so the solve reads the lens instead of copying it.
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
| `props/props.zig` | prop vocabulary + the `INFO` table; `displayName`/`group`/`stock` are exhaustive switches. `decks`/`stack`/`climb` are the ladder's and the deck's |
| `prop*.zig` | meshes by family — `propart` (palette + weathering), `propruins`, `propgold`, `propbuild`, `propvillage`, `propmarket`, `propforge`, `proprock`, `propwood`, `propflora`, `propfungus`, `propcoral`, `propash`, `propbone`, `propfx` |
| `foes/foestat.zig` | the pools the bench lays over a fresh body — one multiplier per kind, applied in `foe.resetGroup`/`resetRoles`, and where the authored HP is LEARNED from the first body made |
| `foes/foe.zig` | THE FOE STANDARD — contract, `Blade`/`strike`/`weaponReaches`/`Blow`, `Trail`, particles, `Leash` |
| `foes/npc.zig` | THE FOLK, all three on the hero's scaffold — the wanderer's staff, the caravaneer's neck and muzzle, and MOSSBEARD, the tree smith whose idle IS a hammer stroke |
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
| `foes/fungaldeer.zig` | fungal deer + `Herd` — quadruped rig's FOURTH user + a stalk, a bloom, 7 petals and a rack. The flower stands off its back for good and OPENS to spit spores that HANG before they home; the antlers are what it does cornered |
| `foes/shroommage.zig` | mushroom mage + `Ring` — the fireball BOUNCES, so it punishes backing off |
| `foes/fenlurker.zig` | fen lurker + `Marsh` — never leaves the water; sunk it is unreachable. Counter is DRY LAND |
| `foes/sporegolem.zig` | spore homunculus + `Host` — `ARMOUR` is the creature; fire and lightning pass through |
| `foes/skitterer.zig` | bone skitterer + `Clatter` — walks ON ITS RIBS; the eye SHUTS before the spine slams. What a priest raises |
| `foes/ancientpriest.zig` | ancient priest + `Crypt` — never melees; claws a skitterer out of bare earth far off, breathes COLD close |
| `foes/hollow.zig` | tolling hollow + `Belfry` — the BELL on its back calls every body inside `TOLL_R`; refused inside bite reach |
| `foes/slumberbloom.zig` | slumber bloom + `Bed` — a rooted FIXTURE with no blow at all; the only SLEEP source, and it cannot follow |
| `foes/cinderwake.zig` | cinder wake + `Scorch` — the hazard is LAID by its own feet, continuously; a standing wake is safe ground |
| `foes/rotgorger.zig` | rotgorger + `Gorge` — quadruped rig's THIRD user; EATS THE DEAD, kin included, and breaks off mid-fight to do it |
| `foes/birchwight.zig` | birchwight + `Stand` — the only counter that is also an escalation: CAUGHT it is faster and sets you alight |
| `foes/salthusk.zig` | salt husk + `Pan` — the weakest thing on the field and the only one whose KILL is the dangerous part |
| `foes/fishman.zig` | fishmen + `Shoal` — the SECOND warband, held together by a NET; netter, spearman, shaman are one move in three |
| `foes/blinkbat.zig` | blinkbat + `Roost` — a flyer that never travels: it BLINKS onto your flank, bites once, blinks out |
| `foes/fungalduo.zig` | THE FUNGAL DUO + `Vanguard`/`Conclave` — swordsman and magus, one encounter, two bars |
| `foes/owlbear.zig` | owlbear + `Perch` — THE FIRST CONSTRUCT, and a carving until you walk inside `WAKE_R`: the eyes lead the stone by half the wake, and the answer to being crowded is a hop back that fans stone quills down the bearing it left on |
| `play/combat.zig` | `Vitals`, `Stamina`, `Focus`, `Regen`, guarding rules, `HitOutcome`, `Elem`/`Resists`, spirits. THE place to retune feel |
| `play/liquid.zig` | WHAT STANDING IN A PAINTED POOL COSTS — one `Soak` row per `wf.Liquid`, billed the way a cloud bills |
| `play/stats.zig` | the sheet — seven attributes, the bar curves, the ONE skill curve (`scaleFor`), `inert` |
| `play/passivetree.zig` | PoE2's tree radially: three arms out of one hub, the gates, `Bonus`, the wheel |
| `play/item.zig` | item vocabulary, `Use`, **`Equip`/`Wear` (the GEAR table)**, the `Bag` |
| `play/counter.zig` | THE COUNTER — shop and smithy as one `Trade`; `STOCK`, `stoneCost`/`coinCost`, and the one `take` that spends. Headless and tested |
| `play/chest.zig` | openable boxes; contents read off the placing op (`Op.loot`) |
| `play/rest.zig` | bonfire + campfire — phase machine, the seat, the fire's own screen; `isRestKind` |
| `play/souls.zig` | THE DROP — what a death leaves, the gold bloom, the walk back |
| `play/tune.zig` | THE STATS BENCH — one `Table` per sheet (spells, ailments, armaments, armour, trinkets, the bag, foes, the hero, every named blow, the passive board, drops, liquids, trade), a getter and a setter each, the base read back at `init`, and `tuning.cfg` written as the DIFFERENCE |
| `play/drops.zig` | one row per `FoeKind`, guaranteed + rare, and **the one thing LUCK reads** (rare weight only) |
| `play/pickup.zig` | the glow a drop stands as; `REACH`, between `chest.REACH` and `souls.REACH` (`rest.REACH` is the widest) |
| `play/award.zig` | the FIRST-TIME card and the toast strip; `seen` is what makes a kind new, and `carding` holds the world clock |
| `ui/hud.zig` | ER HUD, the pad-glyph kit, the day dial, the boss bar, and the ONLY path to draw/measure text |
| `ui/ui.zig` | editor widget kit; `Ctx.anyHot` gates world clicks next frame |
| `ui/uiart.zig` | chrome DRESSING shared by hud/menu/book/ui |
| `ui/itemart.zig` | pictures of things — armaments and bag items as objects, sized by the caller |
| `ui/icons.zig` | editor glyph set, drawn from primitives (vector, not an atlas) |
| `ui/book.zig` | THE CHARACTER BOOK (pad START) — paper doll + ten quick sockets, the bag, the sheet, the piece-under-the-cursor card |
| `ui/counterui.zig` | the counter's panel — the DIALOG's shape over a running frame, not the book's; every number off `play/counter.zig` |
| `ui/menu.zig` | boot screen, pause/debug menu, sound LEVELS, retro filter rack |
| `ui/editor.zig` | THE EDITOR (Menu > Editor), layered StarEdit-style; biggest file, next split candidate |
| `ui/tuneui.zig` | the bench's face — the dial column, drawn both in the editor's Stats sheet and beside the model in the object viewer |
| `ui/objview.zig` | object viewer + the JUKEBOX + the FX BENCH (`elemfx`'s cells with their numbers printed) |
| `save.zig` | THE SLOTS — three files in the map's own `key: value` grammar, each with its picture |
| `core/audio.zig` | ~190 synthesized voices through one tape-style `master`; three submixes; read as recipes |
| `core/rumble.zig` | XInput directly (raylib's GLFW backend stubs `SetGamepadVibration`); holds `PAD` |
| `shots.zig` | the headless harness — never in context while working on the loop |
| `core/collision.zig` | 2D XZ capsule/circle push-out, `blocksSight` |
| `core/mathx.zig` | ground-plane + vector/angle helpers, seeded `Rng`, `gutter` |
| `core/bake.zig` | one-way door that emitted the first map from the old code-authored regions |

**A NUMBER THE BENCH CAN MOVE IS A `var`, AND ITS BANK IS THE `const` BESIDE IT** (`play/tune.zig`, on
`core/audio.zig`'s arrangement). The pattern is one table renamed and one line added — `SPELLS_BANK` stays the
authored const and `SPELLS` becomes the live copy every reader takes — so a row re-authored in the source flows
through to a `tuning.cfg` that never mentioned it. What that costs: anything that read the table AT COMPTIME has
to be pointed at the bank (`combat.ailBank`, `item.equipBank`, `item.priceBank`, `combat.bankRow`), and a
creature's ring is asked for rather than copied (`game.aggroRing`) so a baked table cannot go stale against an
edit. Identity — a name, a socket, which scroll a spell is on — reads the bank on purpose: it is not a tuning,
and a comptime string is built out of it.

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
- **HE HAS HIPS AND KNEES, AND THEY ARE THERE BECAUSE A CYLINDER IS CAPLESS** (owner: the tops of his legs run up
  to the torso and just cut off). Both leg meshes were bare `addCylinder`, open at every joint — the thigh's mouth
  sits AT the hip, so a swung leg showed a flat ring and its culled interior with nothing between it and the
  pelvis. A ball at each joint seals the mouth and reads as the joint: wider than either cylinder there, and
  inside the belt's own half-width (0.235 H against the hip's 0.090), so no standing silhouette changed. The ogre
  had this right from the start (`ogre.limb` caps with a blob) — **the reference rig was the one breaking the law.**
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
- **A CREATURE'S FLINCH IS HEALTH TAKEN IN BLOWS OVER A PERIOD, NOT A COUNT OF BLOWS** (owner: per hit isn't
  fair to dot builds — not that dots build stun, only hits do). On the foe side `Vitals.strike` pours
  `FOE_POISE_PER_DMG` of every point a HIT takes into the poise pool, and a blow's own `poise` is
  ignored; a drip pours nothing. 0.82 puts his base blows on the old scale (13 → 10.7 where the light swing
  carried 10 poise, 27 → 22.1 where the heavy carried 22), so a creature's `poiseMax`, sized between those, still
  means what it meant — and IS the damage it shrugs off inside the refill window. His own stagger keeps the
  blow's `poise`: the WEIGHT of what hit him. **A blow that refuses the flinch must hand the pool back** — the
  knight's door and the greatsword's hyper armour both restore `poise` (and stance) after `foe.reached`, since
  stripping a blow's `poise` no longer does anything; a bloomed fungal deer does NOT, so the light poke a shut body
  shrugs off flinches an open one — the window paying out twice.
- **NOTHING BUILDS ON A BODY ALREADY STUNNED** (owner) — neither pool, and not the lightning meter: the stagger
  is the punish window it earned, and stacking the next one inside it is doing one thing over and over.
- **YOU CANNOT DO ONE THING OVER AND OVER** (owner). Each flinch, break and status proc on a creature leaves WEAR
  on that channel (`lightWear`/`heavyWear`/`ailWear`), the next taking (1 + wear × `LIGHT_WEAR`/`HEAVY_WEAR`/
  `AIL_WEAR`, 0.6/0.6/0.7) as much; wear halves every `WEAR_HALFLIFE`. Measured: 5 blows for the first
  flinch, 7 for the second. Creatures only — bosses do not get to learn him.
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
- **A MOVE IS JUDGED BY THROWING IT, NOT BY LOOKING AT IT.** Every blow goes through the REAL `update` at a hero
  stood across its OWN band — the gather aiming, the strike tracking and stepping, the man shoved out to
  `closestApproach` as `env.resolveActor` would — and must bill a hit at every stand. Two creatures carry the
  test now (`knight`'s THE SWORD IS SWUNG AT THE MAN WHERE HE STANDS, `ogre`'s THE CLUB LANDS ON THE MAN WHERE
  HE STANDS) and it is the judge for the third: a strip or a shot is not.
  - **AND A BEARING THE KIT CANNOT BE BROUGHT ROUND TO IS A HARD GATE AT THE CHOOSE**, never a lower score — a
    whiff is not a worse option, it is not an option. **The gate is SOLVED off what the wind can actually turn**
    (`ogre.slamBearing`: the rear-back's share of `TURN_RATE` over its own duration, plus what the kit subtends
    at that stand), so retuning either end cannot leave it behind. The ogre's slam had no gate and was handed
    out at any bearing inside `SLAM_R`: thrown at a man 170° off he came round to 64° and billed nothing.
  - **OFF THE GATE HE LOOMS, AND LOOMING IS THE TURN** — `.wait` is `enterIdle`, and idle faces the quarry at
    the FULL rate. A gate is only a hole if the state it falls through does nothing.
- **A BODY THE NECROMANCER CAN USE IS A `raisable`/`reraise` PAIR AND A `heldOpen` FIELD** — nothing else, and
  no edit to `game.markVigil`/`applyRaises`, which key off `@hasDecl`. The field is named for what it does to
  the BODY, not for the creature doing it: one name for both had `foe.dissipate`'s probe matching the caster.
- **A multi-kind group answers for its own members** — `kind = null` in `FOE_GROUPS`, each member exposes
  `kind()`. A group with anything else on the field (sacs, acid) exposes `clear()`.
- **Anything the map can post is a `wf.FoeKind`, APPENDED never inserted** (editor unit brushes are pinned to
  that enum's order at comptime), plus `foeName`, a `unitTips` line, a `unitIcons` glyph and a `foeSwatch`.
  Several kinds of one creature go in as a CONTIGUOUS RUN, pinned at comptime.

### The Bone Knight (`knight.zig`) — first boss

Anor Londo Sentinel (docs/GIANT_KNIGHTS.md) on the ER knight brain (ELDEN_RING.md §7). 900 HP, five strokes
plus swat / hop / leap / shove / charge / fall. Memorization and attrition, never dice.

- **THE DOOR NEVER BREAKS; THE MAN BEHIND IT DOES.** No stamina pool on the door. A share of stance passes
  through (`TOWER_STANCE_PASS`, small) so frontal pressure earns a stagger, expensively. No poise ever — the
  door may not flinch him (`tryHit` hands the pool back after a blocked blow, since a creature's flinch is now
  the DAMAGE it took), and `POISE_MAX` is the damage he shrugs off inside the refill window. **TWO PARRIES
  break the stance** (`PARRY_STANCE` over the shared `combat.PARRY_HIT` 46 — owner: good parry potential,
  the player should feel like a badass); it was three, and the third never came.
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
- **A SHIELD IS CARRIED, NOT WELDED TO THE FOREARM** (`hangUpright`, `HANG_TIP` — owner: it goes up in the air
  like a retard, or the sword goes through it). Strapped rigidly, every roll of the forearm rolled four and a half
  metres of oak, and NOTHING WAS ASKING: the pins were three instants of `doorNormal` and five strokes of
  clearance. Walked across every state he has, the plank INVERTED (its own up axis at −0.82) and its foot climbed
  to 6.87 m over a 5.11 m crown; a stagger flung it horizontal at 5.49 m; the SLAM had the hub 4.15 m off a 0.98 m
  strap — the door left his hand, flew to 10.14 m and came back down. So the arm AIMS it and nothing else: the
  face may tip `HANG_TIP` off his own horizontal and no further, and the plank length is then whatever is
  left of his UP — his, not the world's, so a toppled body takes its door down with it. Inversion is impossible by
  construction rather than by tuning a pose away from it. **The SLAM is the one exemption and it is a FRACTION,
  not a flag** (`slamDrive`): laid flat there is no upright to solve for, so the length comes off his FORWARD and
  the far end lies out in front. Exempting the whole move let the HAUL through, and the haul was the 7.41 m.
  **AND THE STRAP IS A LENGTH, NOT A SUGGESTION** — a move own carry (`slamCarry`, `SHOVE_CARRY_*`) may swing the
  hub round the fist and may not take it further off than the grip. Measured now, every state: plumb ≥ 0.86, foot
  ≤ 2.45 m, hub 0.98 m on a 0.98 m strap, and a test walks all twenty of them.
- **THE DOOR IS STRAPPED TO THE FOREARM** (`shieldXf`, `calibrateShield` — owner: it floated off his arm and
  hung at bizarre angles). Position AND orientation come off the wrist bone through one fix solved at spawn, so
  the GUARD is pixel-for-pixel what was authored (square across his front, pulled onto his centre line, foot
  0.26 m, top 4.76 m) and from then on the arm carries the plank rigidly. Oriented off the BODY, the fist only
  ever supplied a position: the plank stayed square to his front while the arm swung out, and left the arm
  behind. **THE ANGLE IS THE ARM'S NOW, SO EVERY POSE THAT PRESENTS THE DOOR IS PINNED ON WHERE THE FACE
  POINTS** (`doorNormal`): forward on guard (z 1.00), forward at the ram (0.99), down at the slam (y −0.95),
  and the hub never further than the grip from the fist. Consequences that follow from the strap:
  - **A shield is driven with the elbow FOLDED and the body behind it.** A straight-arm punch turned the plank
    110° with the forearm and rammed its edge; the bash swings the upper arm 56° and OPENS the elbow by the
    same (`BASH_HIT_SH` 62 / `BASH_HIT_EL` −70), so the forearm keeps its line, and the lean and lunge carry it.
  - **`twist` turns the plank with the torso.** Wound to −58 the bash's door faced his own left; +22 at the
    ram faced it 46° off the man; −16 squares it.
  - **On the LEFT arm a positive abduction channel folds it ACROSS the chest** (the guard's pull), so "out to
    his left" is the negative sign (`SWIPE_ABD`, and `SWIPE_SH` pitches it BACK): out left and back,
    edge-on, behind the shoulder plane. Raised overhead instead, a 4.5 m plank hanging 3.7 m below the fist
    swung over his head onto his sword side.
  - The slam's pitch (`SLM_PITCH_DOWN` 30, was 66) — the arm's own drop supplies most of it now.
- **ANY ROTATION OF THE DOOR IS ABOUT ITS OWN CENTRE, NEVER ITS GRIP** (`SH_CENTRE_Y`). Gripped high like a
  pavise, a pitch about the hub sweeps four fifths of a four-metre plank through the knight.
- **THE ARM CANNOT CARRY IT — THE MOVE HAS TO** (`slamCarry`): the fist travels ~1 m and the door is 4.
- **EVERY SWORD STROKE TAKES THE DOOR OFF HIS FRONT** (`swipeOpen`) — sweep, second sweep, overhead, THRUST
  and the sword-side flick; the bash keeps the guard because the door IS the bash, and so does the shield-side
  flick. (The thrust used to keep it, and its point ran straight through the plank hanging on his centre line —
  owner: the sword is going through the shield.) **THE SWORD COMES HOME FIRST, THEN THE DOOR** (`RECOVER_HOLD_K`
  0.22, `RECOVER_BACK_K`, `SWIPE_SHUT_K0`): the End Pose is held, the arm is back at the carry by 40%
  of the recover, and the door shuts after it — shutting earlier it met the sword still out in
  front. **A test throws every sword stroke wind-to-recover and measures the blade's nearest approach to the
  door's face** (`bladeDoorGap`): 0.64–0.77 m now, against a 0.36 m clearance; it was 0.05–0.16. **THE
  MECHANIC AND THE PICTURE ARE ONE CHANNEL** — `guardUp` and where the door actually is, test-pinned together.
- **HE TRACKS LIKE THE OGRE, AND THE WINDOW IS THE COMMIT — NOT THE FLANK** (owner: the ogre is harder, the
  knight is dull). `TURN_RATE`, pinned into the ogre's class and under it (`ogre.TURN_RATE`,
  public for exactly this). He was at 0.68 — slower than the 0.80 a WALKING man carries — so a stroll in
  circles was the whole counter and most of the fight was him waiting. **YOU CANNOT OUT-CIRCLE HIM ON FOOT
  ANY MORE**: a sprint round him is 2.40. What he gives you instead is what the ogre gives you — the heavy
  commits. Quick rows hold you (`SWAT` 4.80, `THRUST` 4.40, `BASH` 4.00, against the ogre's swipe at 5.40);
  the heavies let go (`SWEEP`/`SWEEP2` 2.00, test-pinned under `TURN_RATE` and under half the swat's); the
  OVERHEAD lets go entirely at 0.
- **BUT HE DOES NOT TURN ON THE SPOT** (owner: step-turn as needed — "oh he's not looking, OH WAIT HE IS").
  Idle holds its facing; what moves it is the STEP-TURN (`STEPTURN`, a planted 62° pivot, taken past
  `STEPTURN.least` 30° — over the bash's 26° gate, inside which he throws from where he stands), the hop, and
  the GATHERS, which aim at the full `TURN_RATE`. So where he is looking is a fact you can read and be wrong
  about: the wind coming round onto you IS the "oh wait".
- **AND "DULL" IS A MEASUREMENT, NOT A FEELING** — 45 s of a hero walking a ring round him is 21 blows thrown,
  93% of the fight committed, and no lull longer than 0.73 s. It was 30 blows at 91% with a 2.23 s lull when
  he pivoted on the spot and threw strokes that could not reach; the time between blows is now hops,
  step-turns and the fall's aftermath — MOVES, not waiting — and every blow is thrown from a stand it can land
  on. Test-pinned, because the failure it guards is the fight going quiet rather than anything going wrong.
- **EVERY STROKE LANDS ON THE MAN WHERE HE STANDS** (owner: "he is swinging at emotions"). Measured, none of
  them did: the sweep was wound HIGH ACROSS his body and crossed his front 4.8 m up, un-live, coming down to a
  man's height only out on his sword flank; the overhead and thrust ran a metre right of a squared man on the
  shoulder's own offset; the sword swat was a flick at his right flank; the shield swat's blow was tested on
  the SWORD, which was at his hip. Only the door connected. So:
  - **THE ARCS ARE AUTHORED LOW AND THROUGH THE FRONT.** The sweep is a forehand cocked behind his right hip and
    ripped across at ~1.3 m (`SWP_*`, fist brought down to ~2.4 m by `lean` 40 — at 2.7 the root cleared a man
    at his boots); the second sweep is a SECOND FOREHAND, the blade drawn back low across his front to the right
    hip (un-live, the whole 0.58 s a tell) and ripped across again — a backhand from the left had nowhere to
    cock once the door stood edge-on behind his left shoulder; the overhead is
    ADDUCTED across the chest (`OVR_HIT_ABD` — a blade pointing straight down barely answers `armSweep` or
    `twist`); the thrust rides a near-LEVEL arm with the blade angled down off it (`THR_HIT_SH` 80, `tilt` −10)
    so the point is out at full stretch at a man's chest, carried onto the centre line, and its lunge is a POKE
    (0.16 — at 0.60 the fist ran PAST a man inside 4 m); the sword swat is flicked from the hip across the front
    with the blade pointing OUT (hung near-vertical, 82° of shoulder sweep moved the tip 30°).
  - **THE PIN IS THE REAL UPDATE**, out to `bandR` — where the AI actually picks it.
  - **NOW THAT THEY LAND, THEY ARE SLOWER AND HEAVIER** (owner): every wind is up ~15% (sweep 1.15 s, sweep2
    0.58, overhead 1.00, thrust 0.62, bash 0.64, swat 0.60 — more predictable), damage up ~12% (swat 16, sweep
    33, sweep2 29, overhead 46, thrust 25, bash 30; the `Weight` rule still caps a HEAVY under 34).
  - **EVERY GATHER ENDS IN A HANG** (owner: the swing tells could be better; `.hold` is how a bait is written).
    The sweep, bash and thrust winds now end with the cocked pose held still for the last seventh, like the
    overhead always did; the swat keeps its `windHold` hang; the second sweep's whole 0.58 s re-cock is drawn
    low across his front, un-live.
- **THE SWORD IS CARRIED HIGH — BLADE UP PAST HIS SWORD SHOULDER** (owner: the sword goes through it; use your
  judgment of how bodies work). **WHAT THIS REPLACES:** the carry was Pflug — hilt at the hip, point presented
  forward-down. On a body whose door covers his whole right side out to 1.54 m, the rig cannot put a point past
  that edge without throwing the arm after it: MEASURED, the point sat 3.66 m off his centre line — 2.6 m
  outboard of his own shoulder — and 1.37 m BELOW the hilt, which is Alber and not Pflug. PHOTOGRAPHED it read as
  a pike carried out sideways, and it was the reason every clearance was tuned rather than structural. Nobody
  fighting from behind a pavise presents low past its edge: the sword lives high. `CARRY_SH` / `CARRY_EL`
  / `CARRY_ABD` −2 / `CARRY_TILT` 150 / `CARRY_SWEEP` 30 — SOLVED, not dialled, by sweeping the four channels
  against a target and taking the best that cleared the plank. Hilt at the sword hip (1.33 m right of centre,
  3.09 m up), point 6.09 m up: 0.98 m over his own crown, 0.63 m off the pauldron and 1.24 m off the helm. **The
  clearance is STRUCTURAL now** — a blade overhead cannot be swung into a plank at his side — and the whole kit's
  worst blade-to-door approach went from 0.11 m to 0.38 m against a 0.36 m clearance.
  - **AND EVERY GATHER NOW STARTS FROM HIGH**, so the drop into the cock is the tell rather than a draw-back.
    Raising `CARRY_SWEEP` past zero flipped the bleed into the shield arm (`SHL`'s `ry(armSweep * 0.30)`) and
    carried the door 0.13 m further out: `BASH.reachOut` was RE-MEASURED to 0.94, and `SHOVE_BAND` came down to
    1.18 to keep the shove's band inside where the flank answer becomes the sweep.
  - The door owns his centre line and the sword the right of it, as before. **Head-on he is still a wall and
    nothing else**: door top 4.78 m under a 5.11 m crown, so 0.33 m of helm shows over 4.5 m of oak, and
    `combat.withinArc` centres the block on his facing — which is why the plank may not be slid off centre to
    show him.
  - **REACH IS MEASURED DOWN HIS FACING, WHILE LIVE, THROUGH THE REAL UPDATE** — never at the bearing the kit
    flies furthest (the gather aims him square, so a flank number is a distance nobody stands at), never before
    the impact frame (picture, not reach), and never off a keyed replay (the springs lag the keys by a few frames,
    and a replay put the swat's crossing before its own impact and read a third of its reach). Sweep 3.72 m,
    sweep2 4.73, thrust 4.08, over 2.83 (the kit alone — its LUNGE carries the drop out), swat 3.20, door 1.90;
    each `reachOut` is that number and a test holds them within [−0.05, +0.65] of it.
  - **THE LUNGE ONLY COUNTS AS FAR AS IT HAS LANDED WHEN THE KIT CROSSES HIS FRONT** (`Attack.stepLands`,
    measured; `bandR` is trigger + step × that). A held End Pose keeps the kit out to the end (thrust, door 1.0;
    the overhead's blade is in the earth by k 0.55, 0.90); a sweep passes the front ONCE — the forehand at k 0.64
    with 0.87 of its step landed, the backhand at k 0.39 with 0.63 — and the rest of the lunge was reach the far
    stand never saw.
  - **A STROKE HAS AN INNER EDGE TOO** (`Attack.reachIn`, `nearR`) — the thrust's point rides level off a
    near-horizontal arm and a man inside 2.65 m is under the fist. `weigh` and the string links skip a stroke
    whose dead zone or far edge holds the man: a whiff is not a worse choice, it is not a choice. Sweep, sweep2,
    swat and door are pinned at 0.
  - **THE SHIELD-SIDE SWAT IS THE DOOR'S FLICK** — `doorSwings` puts the blow on the shield, and
    `swatTriggerR`/`strokeBandR` price it at the bash's reach (2.85 m against the sword's 3.78).
  - Every stroke, both swat sides, is thrown at a hero stood at four stands from its inner edge to 0.97 × `bandR`
    — gather aiming, strike tracking and stepping, the man shoved out to `closestApproach` when the lunge runs
    into him as `env.resolveActor` would — and must bill a hit at every one. Judge a stroke on this before the
    strip; the strips showed nothing wrong.
- **THE JUMPBACK IS A LAST RESORT** (owner: less jumpbacks). Every door to the LEAP — the rear-sector and
  outer-flank picks in `classify`, `counterFlank`'s spine answer, the swipe-and-leap chain — asks `harried`:
  `RETREAT_AT` of max HP banked at this spot (comptime-pinned over 1.5× `REPOSITION_AT`, which keeps
  pricing the shove and `W_PRESS`). Pressure that only warrants a reposition never buys the leap. **One meter,
  two tiers** (`foe.Sense.pressed` with the creature's own shares) — the pattern for any creature that must not
  flee at the first scratch.
- **AND HE SHUTS THE GAP RATHER THAN STANDING IN IT** — the HOP is the quickstep: 3.2 m in 0.54 s on a 2.6 s
  clock, taken on PRESENCE (a man circling him, or the thrust band with the thrust spent). At 1.6 m on a 7.5 s
  clock, gated on damage already banked, it fired about never and the thrust band was where you healed.
- **A GATHER TURNS HIS SHOULDERS, NOT HIS FEET** (`GATHER_SWEEP_MAX`, `holdWindSweep` — owner: he tracks a
  bit too much between attacks, needs a bit more room to get behind). The RATE is still his full `TURN_RATE`; what
  is capped is the TOTAL a wind may bring round off the facing it STARTED from, so a wind-up can no longer erase
  ground the whole recovery bought. **The step-turn was not the culprit** — measured, a walked ring drew only 6 of
  them in 45 s; every GATHER was, each aiming at full rate for up to 1.15 s, which is 211°. Past the cap the
  answer is the STEP-TURN, a move you can see coming. Measured after: a full gather from dead behind leaves him
  120° off (the rear sector starts at 110, so the FALL is still the answer there), and a walked ring puts you
  behind him 25% of it against 17% — with 20 blows still thrown and 95% of it committed, so the dullness law
  holds. `GATHER_SWEEP_MAX` must stay under `180 − FALL_SECTOR` or the back pocket closes.
- **THE DOOR IS A MASS, SO ITS CHANNEL IS CHASED AND NEVER ASSIGNED** (`tickDoor`, `DOOR_EASE`, `seatDoor` — owner:
  it flies around off his hand like a kite; fix his arm motion and keep the shield held). The strap already held
  the hub at the fist and the plank already could not invert; what was left was SPEED. `swipeOpenWant` and
  `shoveAcrossWant` are SCHEDULES with seams in them — a state changing, `shoving` clearing — and they were read
  STRAIGHT into the arm, outside the spring bank that smooths every other channel. Measured: the hub crossed
  **4.3 m in ONE FRAME**, at up to 260 m/s. Both are chased now, **and `guardUp` reads the CHASED value**, so the
  mechanic and the picture stay the one channel and neither can step. Worst frame in any move is now 1.08 m, in
  the slam's own haul, and a test walks all fifteen.
  - **AND THE HAUL IS SPREAD OVER THE GATHER** (`SWIPE_LEAD_K`, `SWIPE_LEAD_TO`): the whole 96° of `SWIPE_ABD`
    plus 82 of yaw used to go in 0.126 s — 762°/s, a snap and not a motion. The plank now leads to
    `SWIPE_LEAD_TO` through the wind, which sits UNDER `guardUp`'s own 0.5 threshold: **the picture leads the
    flag and may never trail it.** The shut got its time back the same way — the sword's road home is UP now, so
    `RECOVER_BACK_K` came down to 0.40 and `SWIPE_SHUT_K0` with it.
  - **AND THE FACE ITSELF IS CHASED, WHICH IS THE LAST WORD** (`turnToward`, `DOOR_TURN_MAX`). Easing
    every channel under it was not enough: the arm's own roll has singularities in it, and a counter yanking him
    out of a slam re-aims the whole basis in a frame. A 120 s chaotic-fight soak caught **113° of face turn in
    ONE FRAME, standing in idle** — a translation test cannot see that, because the hub barely moves while four
    and a half metres of plank whips. Worst now is 14.5°, and turning the cap off puts it back to 60, so the
    chase is doing the work. **The tip is clamped AFTER the chase, not before** (`clampTip`): a slerp runs the
    great circle between its ends, and between two legal near-horizontal faces on opposite bearings that circle
    goes over the POLE — clamped only on the way in, the chase itself tipped the plank to 0.62 of upright.
  - **AND `clampTip` MAY NOT BAIL OUT.** With the face pointing straight up there is no horizontal left to aim
    by, and returning the arm's own matrix there handed back exactly the pose the function exists to refuse —
    the soak caught the step-turn doing it, plank at 0.20 of plumb and flat out at 0.94 m. His FORWARD is always
    a legal bearing.
  - **THE SOAK IS THE JUDGE, NOT THE PER-MOVE PROBES** (`MAKE DAMN SURE…`). Debug entries drop him into one
    state from nothing; the seams live in a real fight — a stagger landing mid-swipe, a string billed under a
    wind, a counter interrupting a slam. 120 s, 200 blows landed on him, 29 of his 33 states visited, and the
    four invariants asked on EVERY frame: hub on the strap, no whip, never inverted, never over his head. It
    fails with the frame, the state and the geometry printed, and it asserts its own state coverage so a soak
    that quietly stopped reaching the fall cannot pass having proved nothing.
  - **A CHASED CHANNEL HAS TO BE SEATED.** A move dropped in from nothing — a debug entry, a shot, a test — has
    no previous frame to inherit the door from, so every `debug*` seats it. `.chainwind` IS a link and seats
    `strung` with it; entered at 0 the plank was still across his front while the re-cock swept low through it.
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
- **THE DOOR IS OAK, AND OAK IS NOT A WARD** — `TOWER_NEGATE` against steel, `TOWER_NEGATE_ELEM`
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
- **A FLANK BLOW HE SHRUGS OFF IS ANSWERED** (`counterFlank`) — shoulders get a snap-and-swat, his SPINE gets
  the FALL (the body coming round is the counter, and its aftermath is the reward for dodging it); the leap
  only once he is `harried` and the fall is spent. It reads a blow that already landed on his own body and the
  bearing it came from (world state, never the player's buttons), is clocked, is refused out of anything
  committed, and is **refused outright if the blow staggered him**: an earned punish window is never taken
  back. Same rule for the door's own guard counter (`caught` → `riposteCd`).
- **NEITHER SHOULDER IS A FREE LAP.** The SHOVE (`shoving`, `shoveAcross`, `shoveDir`) hauls the door onto
  whichever flank you stand on, on the bash's own row and clocks, and buys it with his FRONT. SWORD side fires
  on presence; SHIELD side is bought with DAMAGE (`pressed`), or the door would collapse that whole flank onto
  one move.
- **LIGHT AND HEAVY ARE TELLABLE APART BEFORE THEY LAND** (`Weight`): the gather's FIRE says which — none on a
  light, a rim on a heavy, a column on a crusher, and it must be WIDER THAN THE DOOR to be seen at all. A test
  forbids tuning a move's damage up without its tell following.
- **THE MOVES THE BOARDS CANNOT ANSWER GET THE LONGEST TELLS.** Slam, charge and fall carry no parry window
  (`parryable`); their counter is DISTANCE, the sidestep and the roll. `FALL_WIND_DUR` is therefore bracketed
  from BELOW by every one of his own winds rather than by `foe.TELL_MIN`, and the charge's `windDur` 0.42 is a
  floor. **A RUN CLEARS THE SLAM'S DISC FROM THE MARK AND A WALK DELIBERATELY DOES NOT.**
- **A COMMITTED LINE IS COMMITTED AT THE LAUNCH.** The charge's wind aims (allowed 1.4× his turn) and the travel
  steers not at all, test-pinned frame by frame; `brakeDist` integrates to `speed × brakeDur / 2`. Leap, hop and
  charge are all gated at the CHOOSE by `foe.canLeap`.
- **THE DISC IS DRAWN BEFORE IT IS BILLED** (`slamRingTell`) — the blow's own circle walked during the WIND off
  the same `slamMark`/`SLAM.r` the mechanic uses, in EMBER because tan on tan is unreadable.
- **THE FALL IS ANSWERED WITH DISTANCE NOW, NOT WITH A SECTOR** (owner: make his fall an AoE so you have to make
  some distance). The crush strip is still the BODY arriving; a ring off the same mark (`fallMarkOf`,
  `FALL_WAVE_R`) is the GROUND answering, billed only where the strip missed and lighter on all three counts.
  SOLVED against the tell it is drawn through — 4.61 m over 1.83 s, where a walk covers 3.11 m and a run 6.22 m —
  and drawn before it is billed off the shared `ringTell`. Test-pinned by the claim itself: a man who stands there
  is hit and the same man running is not.
- **AND THE BODY GOES BEFORE THE BODY GOES** (`FALL_WIND_TOPPLE`, owner: tilt back slowly before he falls back).
  The wind takes 15° of the topple at the ROOT over its back three quarters, and the drop picks up from exactly
  there — one motion, worst one-frame step 0.016 of the topple. A giant going over backwards rotates at his heels,
  and `FALL_WIND_LEAN` alone was a gather like every other gather.
- **HE ROCKS ON HIS BACK UNTIL HE CAN GET UP** (`rockAmt`, owner) — ±7° about his own head-to-toe axis, which flat
  on his back is a wallow side to side, faded in and out so entering and leaving `.downed` cannot snap him. It
  rides the SAME channel the rollover turns: a body cannot rock about one axis and turn about another and read as
  one mass.
- **A BODY ON THE GROUND IS LOOKED AT, NOT STOOD OVER, AND IT IS NOT HIDING** (owner: make sure targeting works
  well while he is on the ground). Two separate faults, both in `game.zig`: `collision.blocksSight` takes the
  LOWER of its two ends, so a mark that has fallen to 0.4 m is stopped by any knee-high rubble on the line and the
  lock was dropped `LOCK_BLIND_HOLD` into the punish window it had just bought — `foeStaggered` now holds it. And
  `lockPitch` chased the fallen mark down, diving the lens to 57° at three metres and putting the hero own back
  between the player and the window; the mark is floored at the HERO shoulder for the PITCH only, so the reticle
  still rides the body.
- **STOOD DEAD BEHIND HIM HE FALLS ON YOU.** `fallwind` is the one move that steers AWAY from the hero — the
  spine coming round IS the tell. The crush is a STRIP down the line behind him, DERIVED off the rig, carrying
  the biggest POISE and STANCE in the game (`game.blowHeaviest` is a `@max` over it and the ogre's slam) at
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
  own reach so the lane has crossings in it. `GAS_CAP`. **The cloud is the GROUP's, not the knight's** — it
  must keep burning after the body that laid it has fallen — and it carries NO poise and NO stance. **THE
  CLOUD'S EDGE IS THE MESSAGE** (owner: hard to see where it starts): over half the puffs are born ON the rim in
  a tenth-wide band (`GAS_RIM_SHARE`), the inward drift is a whisper, puffs are small and short at a higher
  rate, and `GAS_H` is METRES (1.3), never his scale — at 1.35 × scale it stood 4 m tall and read as fog. **AND
  IT IS HIS EMBER, NOT CHAOS'S VIOLET** (owner: orangish like his tells, so it is never read as poison) — the
  one call site that picks its own colour over `elemfx.sig`, because the cloud is a tell first and an element
  second.
- **THE BOSS BAR** (`hud.bossBarAt`): `game.zig` owns when it shows (`Vigil.boss`) and SUPPRESSES that body's
  floating bar — one number may not be read in two places. `bossK`/`bossFrac` assigned in `init`.
- **AND A NAMED GATE OWNS ITS BOSS'S BAR** (`game.gateEntered`). Where a ward's seal names the creature, the bar
  waits until his own step has crossed that sheet (`env.wardIn`); where nothing names it, the bar keeps the
  aggro ring it always had. The arena — and so where the bar comes up — is the MAP's to say, authored per gate
  in the editor (Sealed by...), never a list in `game.zig`.
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
  (`markWardStep`); the door is only SHUT while a creature the seal names is still standing, so killing them is
  what lets you back out. A gate may not shut on the man in it (`wardClear`). It is a wall to every FOE and
  every LOOK regardless.
- **THE SEAL IS A LIST, BECAUSE A DUO IS TWO** (`Op.boss`/`nboss`, `Op.sealsOn`, up to `wf.MAX_SEAL`). ANY name
  on it holds the door; `boss=-` is a doorway that never shuts. `boss=a,b` in the file, multi-pick in the
  editor, and one name still writes no tail when it is the default.
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
- **IT STAYS DOWN** (`UNDER_MIN`) whatever it finds, and never past `UNDER_MAX`.
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
- **THE TELL IS THE LONGEST THING IT DOES** (`SURGE_DUR`), on top of a visible mound.
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

Never touches you; priority target on any field. 84 HP, 5 poise, 520 souls.

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
- **THE RAISE IS THE LONGEST TELL IN THE GAME** (`RAISE_WIND`), PLANTED for every frame. It turns to the
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

- **IT ZOOMS OUT OF SWORD REACH.** Threatened, it climbs to `HOVER_HIGH` in a third of a second, works
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

### The fungal deer (`fungaldeer.zig`) — the flower is ARTILLERY, the antlers are the corner

Owner's creature, owner's name, and it REPLACED the florid ravager on the ravager's own bones. A leggy stag
with a large flower growing out of its BACK: `wolf.zig`'s 27 bones plus eleven — a stalk off the withers, the
bloom on it, seven petals, and a beam of antler each side of a head this one actually kept. `wolf.legs` still
takes `wx[0..wolf.N]` as its own array, so no bone it solves has moved.

- **THE FLOWER IS NOT ITS FACE, IT IS ITS ARTILLERY — AND THE TELL IS THE COROLLA, NOT A RISE** (owner: no
  stalk rise; open/close on the spore, bigger instead). The bloom stands off the withers the animal's whole
  life at ONE stance (`STANCE_FURL`), a bud the size of its own barrel; for the volley it OPENS — blades built
  as midrib + vanes + membrane lenses, never bare quills (owner: seven spokes read as a whisk) — and spits five
  spores straight up. A heavy stun still blows the bud open (`openAmt`'s hurt branch); nothing moves its seat.
- **THE HANG IS THE MOVE** (owner: they hover for a bit before homing in). `SPORE_HANG` of drifting and
  bobbing before they turn over, then `SPORE_HOME` — under `hero.SPRINT_SPEED`, asserted at comptime,
  so a spore cannot run him down in a straight line. **THE BOB'S RATE HAS TO BE IN THE STEP OR IT IS NOT ONE**:
  added as `A·cos(wt)·dt` this is the integral of the wave, and 0.16 m authored arrived as 0.02 m of wobble.
- **THE STEER IS CAPPED, NOT LERPED** (`mathx.turnToward`, `SPORE_TURN`). `normV(from + k·(want −
  from))` stalls as the angle grows and at dead opposite is a fixed point: measured, 5.15 s to reverse against
  the 1.43 s a cap gives, on a post-hang life of 5.90 s — so the one bearing the hang exists for was the one
  that did not work.
- **AND A THING IN FLIGHT LANDS ON EARTH, NOT ON WHATEVER HE IS STANDING ON** (`foe.landed`, and the magus's
  orb is its other caller). Nothing in `foes/` can reach `env.groundAt`, so the shot carries the floor it was
  thrown from and is spent on the LOWER of that and his own. Asked against HIS alone, a deer three metres below
  him lost every spore of a volley on the frame it left the throat — the throat rides 2.33 m over its own feet.
- **OPEN, IT TAKES MORE DAMAGE** (`frailty`, `BLOOM_FRAIL`) — 1.9x wide, on the BLADE in `tryHit` so the cull,
  the threat and the shield all see the blow that landed. **DAMAGE ONLY**: `poise` and `stance` ride through
  untouched, because `POISE_MAX` is solved to sit between his light (10) and his heavy (22) and a multiplier
  there would quietly put a light poke through it. The window is a punish, not a second stagger.
- **IT DOES NOT WANT TO BE NEAR YOU.** Inside `FLEE_R` it walks away and QUARTERS while it does — a
  straight backpedal is a thing you keep pace with; past `KEEP_R` it closes enough to throw. `FLEE_SPEED` is
  a gallop and `CLOSE_SPEED` a trot: the flight is the animal, the approach is only bookkeeping.
- **THE ANTLERS ARE WHAT IT DOES CORNERED, AND CORNERED IS TWO DISTANCES AND A CLOCK** (the LAW). He is inside
  `CORNER_R` — the ring the flower is useless in — AND the gap did not open this frame, held for `CORNER_HOLD`
  1.15 s, draining at `CORNER_DECAY`. Never a read of what he is holding or pressing. The charge commits to
  the line it loaded on and does not steer inside the drop.
- **HAND-LAID PETALS, AND THE UNEVENNESS IS BOUNDED BOTH WAYS.** Gaps of 34 to 64 degrees against an even
  ring's 51: pushed at the bottom because `k/7 * 360` reads as a gear, capped at the top or the open corolla
  comes back with a bald sector in it.
- **THE FOLD BUYS RADIUS UP TO 67 DEGREES AND SELLS IT AFTER.** A tip's distance off the bloom's axis goes as
  `(BOW+RECURVE)·cos f + sin f`, so `PETAL_WIDE` dialled UP past the peak makes the flower NARROWER. 95 puts
  the ring at 86..108 — straddling flat, so the throat faces OUT, which is what a flower spitting UP needs.
  `PETAL_SHUT` is NEGATIVE and solved from the same radial: a bud's petals converge PAST parallel.
- **THE BLADE IS ONE SURFACE, AND EVERY VANE ENDS ON THE ENVELOPE THE LENSES SEAL TO.** `VANES` a side lie on
  the midrib's own bow and land on `bladeHalfW`; a vane that stops SHORT of the rim stands out past the
  membrane as a loose strand, and that fringe is what made a mop of the corolla.
- **THE STANCE IS RELATIVE TO THE STALK'S OWN REST LEAN, NOT ABSOLUTE** — STALK→BLOOM is already 26 deg off
  plumb, and an absolute angle folds the flower the WRONG WAY (the old furl at +74 laid it over the animal's
  head, 1.65 m in front of its own hip).
- **THE HURT SPHERE HOLDS THE BLOOM AND THE BARREL** — a weak point a blade cannot reach is not one. The bloom
  keeps ONE seat now (2.00 m, test-pinned within 0.12 m across every state), and `wx[ROOT]` translates in Y
  ONLY, so the whole trunk hangs forward of `pos` and `BARREL_MID` is what keeps the withers inside it.
- **A CORPSE WILTS FROM WHATEVER THE BLOW CAUGHT IT WEARING** (`deathOpen`). Snapping shut is a pop and ramping
  from wide is the same pop the other way.
- **`stageGather` AND NOT `stageRise`** — `shots.runMapShots` finds a creature's signature move off `@hasDecl`
  of that ONE name, and under any other the deer goes unshot.

### The fungal duo (`fungalduo.zig`) — two bodies, one encounter

Owner's creature, owner's brief: a SWORDSMAN who stays in your face and a MAGUS who will not let you have the
rest of the floor. Both on the shared humanoid rig at 1.48 of the hero (a 2.66 m crown). **THE HEIGHT IS
AUTHORED AS METRES OVER THE HERO AND THE WIDTHS RIDE IT** (`SCALE`, `HIP_HALF`, `SHOULDER_HALF`) — written out
as their own 1.34 and 1.30 the widths were `SCALE` copied by hand, and the first time the crown moved the body
under it stayed the old build's width.

- **THEY DIVIDE THE GROUND AND NEITHER COVERS THE OTHER'S.** The swordsman owns the ring you stand in
  (`SW_SLASH_R`, lunging 3.4–9.0) and the magus owns everywhere past it (`MG_FLEE_R` to `MG_KEEP_R`
  16.0). The bands ABUT, and that is the whole of the pair: backing off the blade walks into the sprouts.
- **NEITHER KNOWS THE OTHER EXISTS.** No shared brain and no combo table — that would be a script, and the LAW
  forbids reading anything of the hero's anyway. What makes them read as a pair is the geometry.
- **TWO GROUPS, ONE FILE** (`Vanguard`, `Conclave`). A `FOE_GROUPS` row hands back ONE slice of ONE type, and a
  set of strokes and a set of spells are not one type; a role field over both is a union with two state
  machines in it. They share the file because they share the rig, the palette, the pose and the bands.
- **ONE RAIL PER BOSS, AND THE RAIL IS THE ROW'S INDEX** (`game.BOSS_RAILS`, `hud.bossBarAt`). They die
  separately and the fight is which of them you spend the window on, so one pooled bar would hide the only
  decision in it. Each fades on its own clock, and the chip state is PER RAIL — the knight's bar and the duo's
  swordsman both used to mean rail 0, so every frame each wiped the other's frac, fade and chip tail and the
  two drew on top of each other whether or not either was awake. `AGGRO_OF` takes each rail's ring off
  `FOE_GROUPS`, so a bar cannot wake at a different range from the creature it is showing.
- **THE BAND IS THE MEASURED REACH OF THE STROKE, NOT A NUMBER BESIDE ONE.** Thrown for real, the slash lands
  out to 2.35 m; it was handed out to 3.3 and drove past the man at every stand past 2.5. A band wider than the
  kit is a whiff the pick called a plan, and the judge below is what caught it.
- **THE TWO STROKES DO NOT GET THE SAME BEARING GATE, BECAUSE THEY ARE NOT THE SAME SHAPE** (`swSlashArc`,
  `swLungeArc`). The slash SWEEPS, so it gets the wind's turn plus its own arc; the LUNGE is a thrust down one
  line that closes nothing after the wind commits it, so it gets the turn and nothing else. Given the slash's
  allowance it was thrown at 100 deg, came round 9 short, and missed at every stand in its band.
- **THE KIT IS AUTHORED POINTING UP OFF THE GRIP AND `hero.staffFit` TURNS IT** — and the ARM'S OWN FLEX comes
  out of the tilt (`warrior.swingTilt`'s rule). Fitted in the forearm's frame instead, a `tilt` of 94 — level,
  by the convention — put the point 3.73 m up over a hero column that ends at 1.71.
- **THE VENOM IS THE CLOCK ON THE FIGHT.** Chaos builds poison, and a guard answers the DAMAGE and not the
  buildup, so blocking every stroke still breaks the bar in 5. Both strokes carry it or the clock is on one.
- **THE LUNGE IS PRICED AS A COMMITMENT, WHICH MEANS IT IS RARE** (owner: lunges come too often). At
  the old `SW_LUNGE_CD` it came round every 4.6 s measured — near enough the slash's own cadence that the whole
  3.4–9.0 band read as one move on repeat. At the one it carries now it is one throw in ~7.7 s, and the 4 m band bills 3.3 a
  second against 6.9. **AND THE STEEL CAME DOWN A SECOND TIME** (owner: does too much damage) — 23 raw to 18 on
  the slash and 32 to 25 on the lunge, all of it off `dmg`, because the VENOM is the clock the fight runs on.
  That put one slash inside 1.5× of the orb, so the bar the tall-and-sturdy test holds moved onto the LUNGE:
  the orb is pure chaos and cutting it would come off the venom too.
- **THE JUMPBACK IS A REPOSITION AND ITS TRIGGER IS HIS OWN CLOCK** (`crowd`) — how long something has stood
  inside his swing, which is a distance and a clock, never a read of what the player pressed. It lands him
  inside his own lunge band, so what follows it is the lunge coming back.
- **THE MAGUS'S BUNCH IS THE PUNISH AND THE ORB IS THE ATTRITION.** A bunch of four sown AROUND him (standing
  still is what it punishes), 1.9 s of growing, 0.85 s of glowing, then 3.1 m of burst — the cap's COLOUR is
  its clock, because a warning you have to remember is not a warning. **THE ORB IS A DRIP AND THE CADENCE IS
  WHAT SAYS SO** (`MG_ORB_CD`, owner: chaos orbs could come out a bit slower) — the flight stays at
  `ORB_SPEED`. Most of the caster side's 14 a second is the BUNCH, not the orbs; measure before cutting either.
- **THE DISSOLVE IS LONG ON PURPOSE AND A STAGGER SPENDS IT.** Caught halfway out it comes back solid and owes
  the whole cooldown, so pressure through the fade is the answer rather than a race. It leaves SLUMBER MIST
  where it stood, billed as a soak on the bloom's own meter — and the mist does not bill on the frame it
  appears, because the magus leaves it behind as it goes and that would be a blow with no tell.
- **NEITHER CAST HAS A BAND INSIDE THE RING IT WALKS OUT OF** (`MG_ORB_MIN`, `MG_SPROUT_MIN`, both derived off
  `MG_FLEE_R`). `.back` is answered before either, so a lower minimum is a number nothing can ever reach.
- **AND THE ARENA IS A ROOM NOW, NOT A DOORWAY IN OPEN GROUND** — `mycelian_hall` on the bench and
  `fungal_hollow` in the shipped map, the second traced off the rock that was already round the pair (one corner
  per 30 deg, each on the nearest cliff's own collision radius, the fog gate standing as the corner at due west).
- The bench is `worlds/test_fungalduo.world` — the pair on an arena floor with one pillar, at the distance the
  fight is meant to hold. `--map worlds/test_fungalduo.world`.

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
- **RUN IT OUT AND YOU ARE WINDED** (`STAM_WIND_CLEAR`): sprint stays denied until the bar is back to HALF.
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
- **CHIP GETS THROUGH AND CHIP CAN KILL** (`GUARD_NEGATE`), routed through `Vitals.hit`. Stability is poor
  by design: kobold teeth ~15 of 105, the ogre's club ~45.
- **EMPTY THE BAR UNDER A BLOW AND THE GUARD BREAKS** — heavy stagger, and the shield cannot come back up
  until the pool refills. The danger is the NEXT hit.
- **`takeHit` RETURNS WHAT BECAME OF THE BLOW** (`HitOutcome`) and `game.heroTakes` is the ONE place that turns
  it into a felt beat.
- **HE CAN WALK A FIGHT DOWN BEHIND IT** — `hero.GUARD_SPEED` of the walk, capped against the walk, never
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
- **TWO NUMBERS ARE THE DECISION AND THE OTHER TWO ARE SOLVED** — `JUMP_APEX` and `JUMP_AIR`;
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
  A wall is still a wall at any altitude (`h` 3 m against `JUMP_APEX`). **NO `STEP_UP` allowance there**,
  unlike `flyStep`: there is no step-over-props rule to stay level with. **FOES are deliberately still measured
  at `pos.y`** — nothing but the hero has a real integrated height yet.
- **THE LENS TAKES ONLY A SHARE OF IT** (`camera.LIFT_SHARE`, eased). `hero.shoulderPoint` is over the
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
  one — `souls.REACH` against a box's `chest.REACH`, asserted at comptime.

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
- **75 IS THE CAP, NEGATIVE AMPLIFIES** (`RES_CAP`, `RES_FLOOR`). Stored uncapped, capped on READ
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
  RE-PRESSED**: a turn past `AIM_TURN` fires at once and a drift under it carries the repeat onto the
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
  Behind a raised bow he moves at `BOW_AIM_SPEED`, a smaller share of the walk than the shield's.
- **ARROWS ARE FINITE** — `combat.Quiver`, ten plain and five fire (`FIRE_ARROWS_MAX`), refilled at a bonfire.
  The quiver is checked BEFORE stamina is charged. The SELECTED kind is what flies, empty or not, LATCHED at
  `startShot`.
- **THE FIRE ARROW** hangs fire worth `FIRE_ARROW_FRAC` of the shaft's physical ON TOP of it — PoE2's
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

- **ONE TABLE, ONE ROW PER THING** (`item.equip`) — twenty-one pieces, and the numbers are all any of them is (a
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
- **BOTH PAGES SPEAK IN NUMBERS, AND NEITHER CARRIES A BILL** (owner: attack damage in NUMBERS not percents,
  attack speed in some NUMBER corollary not percent; remove stats like roll speed or stamina consumption). The
  rows on the equipment sheet (`book.Der`) and on a piece's own card (`book.GDial`) are what the FIGHT uses:
  light and heavy through `hero.weigh`, the clock in SECONDS through `hero.swingSecs`/`drawSecs`, the guard's
  real negation under `combat.GUARD_NEGATE_CAP`, the arc in degrees, armour AND what its curve turns aside, the
  pools, and the four columns. **A DIAL IS NOT A STAT**: "78% swing time" asks the reader to hold a straight
  sword's own 0.62 s in their head, and no page ever showed them that number to hold. The stamina bills and the
  roll went to a details panel that does not exist yet; the stamina POOL stays on the stats page, because a pool
  is not a bill. `item.effect` still prints the DIALS for the bag page, which has no table under it.
- **BROWSING THE DOLL SHOWS THE PIECE *AND* THE SHEET** (`book.browsing`, `drawGearCard`). What a worn piece
  does was reachable only by OPENING the picker over its socket, and then only as a column beside a candidate.
  The card is the slot under the cursor — a bare hand included, off `item.bareArm` — and the sheet under it is
  the body carrying it; a slot with no gear in it at all (ammo, sorcery, the ten quick cells) gives the sheet
  the whole column back. The card is capped at what the sheet is owed (`derivedNeedH`), `pickBox`'s own rule.
- **THE SHEET IS TWO COLUMNS AND THE ENUM'S ORDER IS THE LAYOUT** (`book.DER_SPLIT`) — what he DOES before the
  seam, what he IS after it. Twenty-one rows down one column overflowed the box a picker leaves them, and
  `rowStep` will not pitch under `rowFloor`, so the tail drew over the panel below.
- **A WEAPON'S FOOTER IS THE HALF A NUMBER CANNOT SAY** (`book.armWords`) — heft, reach, and WHICH SKILL DRIVES
  IT, which had never appeared anywhere in the game. Off `stats.displayName`, so a renamed attribute carries.
- **THE THREE MELEE SOCKETS RUN BACKWARDS TO A `Blade`** (`hero.bladeForWear`), so a panel handed a SOCKET can
  price the stroke standing in it. Pinned against `wearFor`+`bladeOf` at comptime, or a club is clocked as a sword.
- **A BOARD PRICES NO BLOW.** The card and the compare read the offence rows off a socket that actually swings
  or shoots; taken from `item.bareArm` for every held socket alike, a shield printed the bare sword's damage
  beside it — noise as "Damage 100%", a lie as "Heavy attack 27".
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
- **BILLED IN FP AND NOTHING ELSE** — `BOLT_FP`. The wand competes with the flask, not with the roll.
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
- **ALL CHAOS, NO PHYSICAL** — `BOLT_HIT` 25 chaos, poise 14, stance 6. Chaos is the most-resisted column, so
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

- **THE LADDER IS MONOTONE, AND THAT IS THE WHOLE PRICE LIST**: bolt 8, levin 11, roots 12, siphon 13, lance
  14, rime 15, sunder 16 FP (`combat.SPELLS`, which is the price list — the damages are the rows' own). Every
  step up in FP is a step DOWN in raw damage — what the difference buys is a stagger, a hold, HP back, or a
  second body in the cone. A comptime block asserts it over every PAIR, so an eighth spell is priced by the
  rule without editing it.
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

- **THE UNITS PALETTE IS TWO TABS AND THE FOES ARE FILED BY KINGDOM** (`editor.UnitTab`, `foe.homeOf`). Forty
  one icon rows in one column is 1220 px of list in a 738 px panel: **the bottom seventeen creatures were drawn
  off the end of the window and could not be clicked at all.** Foes / Folk, and under Foes a chip per
  `props.Biome` that holds one — the same axis the props are filed on, so the two palettes split the world the
  same way. Tallest tab is 12 rows now. `foe.homeOf` is an EXHAUSTIVE switch (`traitsOf`'s reason: a creature
  cannot be added unfiled) and NOTHING SPAWNS BY IT; `any` is not a dustbin, it is the set that answers every
  chip (`foe.atHome`), which is why it has no chip of its own.
- **THE DIGIT KEYS AND THE PANEL WALK ONE LIST** (`editor.visibleBrushes`). Filtered in one and not the other,
  `3` armed a creature the palette was not showing. **The eraser is in every tab** — a tool, not a category —
  and the tab moves to the armed brush on entry, never the brush to the tab.
- **THE MINIMAP IS FIVE THINGS** (owner) — walls, water, trees subtly, fires, red for the foes. It used to blit
  the whole soil grid, shade the relief and dot every op, which on the shipped map is 16,587 dots over a painted
  floor telling you nothing. **A wall is whatever the camera will not thin** (`props.Info.solid`), which is the
  same set the hero cannot walk through, so the map's barriers and the world's cannot drift apart. **Read off
  `env.placed()`, never off the ops**: a belt of a hundred trees is ONE op, and an op walk drew one tree where
  there is a wood.
- **THE FLOOR IS A MARGIN ON THE LOADED MAP'S OWN HALF** (`env.groundOut`, `GROUND_APRON` with a 60 m
  floor). As a flat `DEFAULT_HALF + 220` a 95 m test bench was a 190 m island sitting in a 1000 m floor, with
  the editor's bound box drawn round the island (owner: "the floor looks larger than the map"). The shipped
  280 m map moves 4 m by this, 500 to 504 — which is the point: it was already right THERE and nowhere else.
  The flat path draws ONE quad built at the widest and scaled (a plane scales exactly, and every field the
  shader reads over it is indexed in world xz); the sculpted path already had the tiles and a skirt.
- **THE DECOR LAYER IS NOT PLANTS** — it is `props.Info.flora`, which holds cobbles, shards and scree too. Small
  accoutrements, whatever they are made of; the layer tip says so.
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
  would cover more. `BRUSH_CORE` keeps the middle solid.
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
- **A CELL IS 5 m** (`SOIL_N` over a 560 m world), the floor on how fine any of this can be. Warps under
  about half a cell do not survive the coverage staircase.
- **AN OLD MAP COMES UP UNCHANGED** — no `soiledge:` row means every cell takes the edge its material used to
  imply (`fillLegacyEdges`: stone cut, everything else soft). The row is only written when some stroke asked for
  something else (`edgesAllDefault`).
- **THE COAST USES THE SAME EDGES, AND THE TABLE IS WRITTEN ONCE** (`shaders.EDGE_K`). The GLSL `edgeShape` is
  GENERATED from that table and `shaders.warpEdge` is its Zig twin, so the shape a map asks for means one thing
  whether it is soil or water. Water USED to bake the shape into the field (`coastWarp`) and then re-facet it on
  a 3.6 m lattice: measured, that left `natural` with 1.6% more waterline than `straight`, which applies no
  wander at all — eight shapes arriving as one smooth blob, because a warp sampled once per 1.25 m cell is
  undersampled by its own wavelength and bilinear filtering then smooths off what survived.
- **THE SHEET DIES INTO THE SHORE; IT IS NOT CUT BY IT** (`WATER_FEATHER_D`, `WATER_FEATHER_MIN`). A domain
  warp whose amplitude beats its own wavelength FOLDS OVER ITSELF, and a hard threshold turns every fold into a
  shard — a `jagged` coast came out as torn paper with islands thrown off it. The soil never had this fault
  because its edge is an ALPHA (`k.z` feathers the coverage ring); water was the one surface asked to end at a
  compare. It fades over the shape's own `feather` now, FLOORED so even one authored to CUT still dies softly.
  The amplitudes are the soil's own and are not the problem — do not go tuning them to chase a hard edge.
- **THE COAST GETS A LOW OCTAVE THE SOIL DOES NOT** (`BAY_FREQ`, `BAY_M`) — bays at ~22 m, in METRES and not
  as a multiple of the shape's wander, or `jagged` gets 8 m of bay and `natural` 4 for no authored reason. It
  moves the waterline and `paintedDepth` follows, so it stays small enough that a painted pond is still the
  pond somebody drew.
- **THE FIELD IS ONE FIELD, FEEDING THE LOOK *AND* THE WADING**, which is why the warp is evaluated on BOTH
  sides: `shaders.waterAt` per fragment, `env.paintedDepth` per query, off the same row. Shaped only on the GPU
  the coast you see would sit up to `warp` metres from the coast you walk into — measured at 1.50 m on `jagged`.
  Anything that reads the field for gameplay goes through `paintedDepth` or it is looking at the wrong line.
- **WATER IS PAINTED, ITS COAST DERIVED** — one bit per cell → a signed distance field (128 is the waterline).
  One field, three effects. The sheet is ONE world-spanning quad. `worlds/test_wateredge.world` is eight ponds,
  one per `Edge`, on bare ground: `--shot-land --map worlds/test_wateredge.world`.
- **FOUR LIQUIDS, ONE SHEET, ONE FIELD** (`wf.Liquid`, `wf.Map.waterKind`) — water, oil, fungal, lava, one per
  cell off the same brush. **THE FOOTING IS WATER'S AND UNCHANGED FOR ALL FOUR**: same coast, same
  `paintedDepth`, same `WADE_MAX`, same `Gait` gate, same `avoid.water`. Three things differ and only three —
  the LOOK, the STATUS it soaks in, and the VOICE.
- **THE KIND RIDES IN THE COAST BYTE** (`env.packLiquid`) — `wf.Edge` in the low three bits, `wf.Liquid` in the
  next two, one point-sampled `u8` per cell. Two ordinals in one texture because they are dilated by ONE walk
  off ONE paint (`env.dilateWaterEdge`) and because a second sampler would be an EIGHTEENTH texture unit, where
  GL 3.3 promises a fragment stage sixteen. The GPU unpacks in `waterCellAt`, the CPU in `env.waterEdgeAt` and
  `env.liquidAt` — and `liquidAt` reads the DILATED field, so a foot on the bank answers with the pool's kind.
- **A MAP WITH NO `liquid:` ROW IS ALL WATER** (ordinal 0), so every map written before this comes up unchanged
  and round-trips byte for byte — the row's own `wateredge:` rule.
- **THE STATUS IS A SOAK, NOT A BLOW** (`play/liquid.zig`, `game.tickLiquid`) — the sporeling cloud's channel
  (`foe.Soak`, `hero.doseSelf`), so nothing blocks it and nothing parries it. **NOTHING DECAYS UNDER A
  CONTINUOUS DOSE** — a dose resets `sinceDose` and the delay is 1.1 s — so `max/build` IS the seconds to break:
  fungal 13.9 s of POISON, lava 7.0 s of BURNING, and clipping a rim is 2% and 5% of the bar. Lava also drips
  4.5% of MAX HP a second in fire: a SHARE of the bar (`Soak.dpsFrac`), so a levelled body cannot walk it off,
  and a DRIP (`hero.burn`) so it never builds the meter a second time. Oil is a look and a sound and nothing else.
- **LAVA IS A LIGHT, NOT A SURFACE** (`sheetGlow`) — written from inside the sheet's material branch and applied
  past the emissive mix, because `emis` rides a vertex alpha the world-spanning quad cannot carry. It also takes
  NO sun lobe: a specular streak on lava reads as wet plastic. Tar's fresnel is the OPPOSITE problem — at
  water's exponent 3 an oil pit came back a flat slate disc from the far bank (0.09 linear over the whole
  surface, 87/255 after gamma), because a sheen over a near-zero albedo IS the pixel. Fifth power, a third the
  amount.
- **BUBBLES ARE ONE HASH TAP, NOT NINE** (`bubbleAt`) — one per cell, centre in 0.3..0.7 and radius under 0.28,
  so a dome can never cross into a neighbour and the 3×3 ring a bubble field usually needs is not paid for on a
  quad that covers the world. They MOUND and then pop; the swell is most of the read.
- **ITS VOICES ARE A BED PLUS A THINNED POP** — one dialled bed per liquid (`audio.setLiquidBed`, off a scan
  bounded to 27 cells a side around the hero) and a pop every ~1.15 s from a reservoir-sampled wet cell
  (`game.POP_EVERY`; the surface pops far more often than it is heard to). **WATER GETS NEITHER**: the wind is
  its bed, and painting a tarn may not add a voice to a map that already sounded right.
- `worlds/test_liquids.world` is one 14 m pool per liquid at (±32, ±32) on bare ground:
  `--shot-land --map worlds/test_liquids.world`.
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
- **THE ANCHOR IS NOT A KEYFRAME.** `SHOT_HOUR` reproduces `gfx.SUN_DIR` — the light this game was
  authored, measured and photographed under, and the bearing `shots.LIT_YAW` is framed off. `SUN_ALT_MAX` and
  `SHOT_HOUR` are SOLVED from it; move `AZ_RISE`/`AZ_SET` and you solve them again. Two tests pin the direction
  and the palette row. `--shot` pins and FREEZES that hour (`game.pinHourForShot`).
- **The controls.** Menu > Debug > `Hour` (Left/Right scrub, Shift coarse, hold to sweep, Confirm holds it); in
  the EDITOR `,` and `.` sweep it and Shift runs (the clock is held there, so those are the only writers) — and
  the same hour is on the World card, as a readout, a quarter-hour stepper and four marks worth authoring at,
  `Anchor` among them. A BONFIRE offers `Rest until morning` / `Rest until evening` — always FORWARD
  (`hoursUntil`). Nothing is restocked there: `hero.sit` made him whole when he sat down. **EVENING IS AFTER
  DARK**: morning 8:30, evening `EVENING_HOUR` (an hour past `SUNSET`, sun DOWN and moon casting).
  Deliberately NOT `SHOT_HOUR`. A comptime assert pins it past the horizon, a test pins `!isDay` and the key
  under a quarter of the anchor, and `shots/147` is that hour.
- **THE FIRE TOUCHES THE CLOCK NOWHERE ELSE.** The old `dim` uniform is GONE: the hour you walk in at is the
  hour you sit in, and the two `Rest until…` rows are the only thing at a fire that moves the light.
- Verify with the strip: `shots/140`–`147` are eight hours of ONE view shot into the light's own quarter,
  `148*` three overheads. The arc is the test — a frame that reads like its neighbour is an hour the palette is
  not earning.

### The weather (`weather.zig`)

**IT IS AN EVENT, NOT A SETTING.** A storm arrives every `DRY_LO`..`DRY_HI`, runs
`WET_LO`..`WET_HI`, ramps 9 s in and 14 s out. Measured over an hour: **9 storms, raining 26% of the
time, dry gaps 162–405 s**. The clock is PURE (`Weather` is seconds and 0..1), so a test runs a day without a
window.

- **TWO STRENGTHS, AND ONLY THE HEAVIER HAS A SKY.** `GENTLE_TOP` against `MODERATE_TOP`, and the
  moderate storm is the minority (`MODERATE_ODDS`). Lightning waits for the storm to arrive (`FLASH_AT`).
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
    to 24 m** at `OPACITY` (from 1.97/m² at 0.44). Spreading the disc IS the thinning: streaks are laid by
    area, so trebling it drops the near field by the same factor while the count barely moves.
  - **THE COLUMN STANDS ON THE MAN, NOT ON THE LENS, AND ITS RIM FADES.** Centred on the camera the disc reached
    24 m behind the lens and 19 ahead of the hero — the short side being the side the frame looks at; and it
    must be a point the camera does not ROTATE, since a lead off the camera's forward slides the sheet sideways
    at 40 m/s when you turn. The rim thins to nothing past `TAPER_FROM` (width goes out, length only part way),
    baked into the geometry because a per-streak opacity is the one thing this renderer has no channel for. The
    heavy sheet's second copy is offset in Y, barely in XZ.
  - **THE HEAVY SHEET FADES IN, IT DOES NOT ARRIVE** (`copyFade`, 3.6 s up, 5.6 s out, topping at `COPY_TOP`
    0.72), so the peak storm is 6.16 columns of blended fill rather than 8.
  - `FALL_MPS` is just over real rain's 7–9. At 21 a streak crossed twenty-three times its own body in a
    second, which is a smear.
  - **A STREAK IS TWO CROSSED CARDS** — a single card is invisible edge-on. Two segments each, so the tail
    fades in the GEOMETRY (`propfx`'s pillar law).
  - **THE SLANT IS WORLD-FIXED** (0.30 across the fall) so turning the camera turns the rain, MEASURED off the
    first shot where 0.17 read as vertical.
  - Draws LAST, through `Scene.beginFade`: no depth written, still depth TESTED, which is what puts it behind
    the wall you are standing under.
- **THE CLOUD TAKES THE LIGHT, AND THE STRIKE GIVES IT BACK** — two rectangles over the frame, INSIDE the retro
  pass. `DIM_MAX` of a cold slate; the flash at 74/46 alpha.
- **BUT THE STORM IS A LAYER ON THE PALETTE, NOT A RECTANGLE** (`daynight.overcast`). Cloud does four things a
  rectangle cannot: puts the KEY out (`STORM_KEY`, so shadows and every `keyAmt` specular go with it),
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
  draws, ~10.8k tris, `MIST_TOP` at full fog. **THE SLOWEST THING IN THE GAME** — 0.045–0.16 m/s, 94 s to
  cross its own width. Banks ramp in and out over 9 s and are re-seeded out past `MIST_R`, never in view. Three
  mesh variants (the repeated-big-prop law).
- **THE DRY SKY HAS BIRDS IN IT** (`weather.Skein`, owner: bird packs of different sizes across the sky,
  distantly, from different angles, infrequently, "just to feel alive"). **IT IS AN EVENT, NOT A FLOCK THAT LIVES
  THERE** — the storm's own law. One flight arrives, crosses, and is gone: measured over an hour, **63 crossings,
  4 to 17 birds, in the sky 28% of the time**, so it is empty more often than not and a crossing is still worth
  looking up at. Gap `SKEIN_GAP_LO`..`HI` **18–62 s** (owner's own number, twice revised — it was 190–520 and he
  never saw one), and the clock runs ONLY on a dry sky (plus `SKEIN_AFTER_RAIN` of settling), so a long storm
  cannot bank up a flight that then arrives the second it clears. A flight already in the air is not deleted by a
  squall; it finishes its crossing. **THE COUNT IS DERIVED IN THE TEST, NOT PINNED BESIDE IT** — a mean gap plus a
  crossing predicts 65 an hour against 63 flown, so moving the gap cannot leave a stale number behind.
  - **AND THERE IS A DEBUG ROW** (`menu.DBG_BIRDS`, owner: I didn't see any) — `DBG_WEATHER`'s reasoning exactly:
    an event on a clock measured in minutes is not a question anybody can sit and answer. It sends one ACROSS his
    view, and the request survives the menu being open (`takeBirds` drains on the first frame after it shuts,
    which is the frame he is looking at the sky again).
  - **THE RANGE IS NOT PICKED EITHER, BUT IT IS NO LONGER SOLVED AGAINST THE HAZE.** `gfx.HAZE_DENSITY` is
    0.013 a metre, so what is left of a thing at range d is exp(−0.013 d) — 9% at 185 m, which is why the birds
    were invisible, photographed. The band is solved against the FRAME now (`skeinNear`/`skeinWide`/`skeinRim`,
    measured 160–284 m), the haze is turned DOWN over it (`SKEIN_HAZE`), and the fade-in is code
    (`SKEIN_FADE_M`) rather than the distance doing it.
  - **A BIRD IS A SILHOUETTE**, so it is opaque and nearly black. At vertex alpha 210 they came up self-lit and
    pale and washed out into the very haze they are read against (the 248+ law).
  - **THE FLAP IS A SQUASH OF THE V, NOT A BONE** — at this range a wing is a couple of pixels and what reads is
    the silhouette breathing. Cheap enough that every bird carries its own period, which is what stops a pack
    beating as one animal; a test pins that no two in a skein share a wingbeat.
  - **DIFFERENT ANGLES IS A RESULTANT, NOT A DIE.** Bearings summed as unit vectors pull 0.38 one way over an
    hour, where 1.00 would be a flight path — "no two in a row within N degrees" is a dice roll that fails on an
    honest sky about a third of the time.
  - One draw a bird, `BIRDS_HI` at the worst and only while a flight is up, against the rain sheet's 4–7.
- **THE SKY IS SMALLER THAN IT LOOKS, AND ANYTHING PUT IN IT IS SOLVED AGAINST `camera.skyTop()`** — half the
  lens less the resting pitch, 0.200 rad, **11.46 deg above the horizon**. That is the whole of the sky a player
  sees without holding the stick up. The birds were authored at 30–62 m up, entering at 96 m and crossing to
  within 56 m: the LOWEST elevation any bird reached over a whole flight was 15.1 deg and the middle of a
  crossing was 48 deg, near enough straight overhead. Sixty-two flights an hour, something in the sky 30% of the
  time, and not one of them was ever on the screen (owner: "i never see any fuckin birds"). **THE HARNESS DID
  NOT CATCH IT BECAUSE BOTH BIRD SHOTS HELD THE LENS UP AT THE FLOCK** — `157b_birds_resting.png` is the frame
  a player actually gets, and a test walks half an hour of sky and pins every bird inside it (3.5–8.3 deg now).
- **THE SKEIN'S WHOLE BAND IS DERIVED, NOT PICKED** (`weather.SKY_SHARE`, `skeinNear`/`skeinWide`/`skeinRim`).
  The ceiling is 0.70 of `skyTop`; the closest the line may come is `HIGH_HI / tan(ceiling)`, so the highest
  bird at the nearest point sits exactly on the ceiling. `HIGH_LO` is the floor because a cliff stands
  15.5 m (`props.cliffParts`) and they used to fly through them. **THE OFFSET NEVER PASSES THROUGH ZERO**: a
  line over your head is a line whose middle is at 90 deg, and the middle is the part you were meant to see.
- **AND THE HAZE IS TURNED DOWN FOR THEM ALONE** (`gfx.Scene.setHaze`, `weather.SKEIN_HAZE`, paired like
  `beginFade`). A bird is not a surface the distance veils — it is a SILHOUETTE, and the haze does not soften a
  silhouette, it deletes it by pulling it to the sky's own colour. At 0.013/m the world's own density leaves 4%
  of a thing at 240 m, which is where the band has to be now; at 0.35 of it, 33%.
- **THE FADE IS METRES, NOT A SHARE OF THE CROSSING** (`SKEIN_FADE_M`). As a fraction the ramp got steeper
  every time the chord came in shorter, and "it never pops" is a claim about the per-frame STEP.
- **THE BED IS THE STORM'S, NOT THE HOUR'S** (`audio.setRain`, `audio.mkRain`) — three bands with a granular
  patter (a hiss alone is tape noise, a low roar alone is a motorway). Does not retrigger while dry. Thunder
  (`mkThunder`) is a ROLL with no transient at its head, and it is the third kind of ambient voice
  (`AMBIENT_EVENTS`): not a bed, not a call, fired by the world.
- Weather does not run in the EDITOR, and `--shot` forces one: `shots/150`–`153` are dry, gentle, moderate and
  the strike, `154`–`155` the fog and one mist bank — forced through the debug row (`game.forceFogForShot`) so
  the air is photographed APART from the rain.

### Elevation

The world is a HEIGHTFIELD you sculpt (Ground layer > Raise/Lower/Smooth/Flat), stored as one QUANTISED height
per lattice point (`HEIGHT_N`, `HEIGHT_STEP`, biased so `HEIGHT_ZERO` is the old flat ground).
Quantised because the file is TEXT and the writer is a run-length encoder. The mesh is TILED (`TCHUNK`), with
normals from the FIELD so two tiles agree at their seam.

- **A FLAT MAP IS THE OLD WORLD, EXACTLY** — `heightAny` false means one world-spanning quad, `groundAt`
  returns `GROUND_Y`, and no `hgt:` record is written.
- **NOTHING SAMPLES THE MAP DIRECTLY.** Env keeps the live copy the visible mesh was built from and
  `wf.sampleHeight` is the ONE sampler both owners call.
- **EVERY PROP PLANTS AT THE HEIGHT UNDER IT** — `uploadHeight` must run BEFORE `materialize`, and a sculpt
  stroke re-materializes on RELEASE.
- **TWO RULES DECIDE EVERY STEP** (`env.walkStep`), either passing: the rise ahead is under `STEP_UP`
  (sized to the encoding — two risers walkable, three a wall), or within `MAX_SLOPE` (tan 40°).
- **MEASURED OVER A FIXED LOOKAHEAD (`STEP_PROBE`), NEVER THE FRAME'S OWN TRAVEL.** Against frame distance a
  240 fps hero ratchets up a vertical cliff. A test pins the rule across four frame rates.
- **A REFUSED STEP IS NOT A STOP** — the uphill component is removed and the rest is taken at full length.
- **FOES GET THE SAME RULES** as a POST-STEP GATE (`game.gateTerrain`). Airborne foes are exempt from the
  terrain rule and from being shouldered — never from `env.resolveActor`. That push-out is NOT rate-limited.
- **BUT NOT AT HIS WATERLINE — AT THEIR OWN** (`foe.wadeLimit`, `env.walkStepPast`). `WADE_MAX` is CHEST
  height on the 1.8 m rig and HIS choice. A creature turns back at `foe.WADE_FRAC` of its own stature,
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

### Decks and ladders — the only two ways off the ground

**A DECK IS THE FIRST WALKABLE SURFACE THAT IS NOT THE LAND** (`props.Info.decks`, `env.deckAt`/`standAt`). Props
were XZ capsules with a ceiling and nothing else; `game.groundActor` asks `standAt` now, so `pos.y` is the deck
where there is one and `groundAt` stays the question about the LAND.

- **A DECK HE IS NOT ALREADY UP AT IS NO FLOOR AT ALL** — the gate is the walk's own `STEP_UP`, which is what
  stops a body on the ground being snapped onto a platform five metres over its head.
- **A `hole` CANCELS THE DECK AT ITS OWN `y` AND NO OTHER** (`env.holedAt`) — a trapdoor, and the ONE way a deck
  is not simply convex. The mesh and the deck are solved off the same constants or it is a floor you fall
  through. One row per storey in `propbuild.WATCH_STOREYS` is that single source: the mesh boards each row and
  `props.WATCH_DECKS` turns the same rows into decks and holes.
- **WALKING OFF A DECK EDGE IS A FALL, NOT A SNAP** (`game.heroFooting`, `hero.startFall`). `groundActor` PLANTS
  past `GROUND_SNAP`, which off a five-metre floor is a teleport with a footstep on the end of it. Only a deck
  does this; the land keeps the snap it has always had.
- **THE LENS FOLLOWS HIS FEET, NOT `pos.y`** (`game.syncLensLift`, `camera.tickLift`'s share). Both jump — a
  plant, a mount, a top-out — while `pos.y + lift` is continuous through all of it. A climb and a fall off a
  deck take the FULL lift; a jump still takes `camera.LIFT_SHARE`.
- **A SOLID CAN HAVE A FOOT** (`Part.y0`, `collision.Solid.y0`) — a LINTEL: the course over a doorway, open to a
  body on the floor and wall to one up on a deck. Four consumers and they must all know: `blocksPoint`,
  `blocksSight`, `env.resolveActorPast`, and **`buildSolids`, which has to carry `y0` into the collider the way
  it already carried `h`** — left behind, the watchtower's doorway came out sealed from the ground up.

**A LADDER IS THE ONE PROP YOU GET ON** (`props.Info.climb`, `game.Climb`). Its own local **+Z is the open side**
he mounts from and stands off (`propbuild.LADDER_STANDOFF`); local −Z is the wall it leans on.

- **IT IS THE FIRST KIND THAT STACKS** (`props.Info.stack`, `Prop.rise`, `env.drawStack`). One mesh drawn as
  whole sections up its own axis, because a uniform `scale` drags the rungs apart with the rails. Every other
  section is turned 180°, or the mesh's own wabi-sabi bands the run like a barber's pole.
- **THE SECTION IS THE AUTHORING GRANULARITY, AND THAT IS WHY IT IS 0.90 m** (`propbuild.LADDER_SEG`, three
  rungs). A run can only be a whole number of them; at 2.40 the band `ladderExit` accepts was narrower than the
  pitch, so against a cliff quantised to `wf.HEIGHT_STEP` most lips had no run that served them.
- **THE HEAD MAY STAND PROUD AND MAY ONLY JUST FALL SHORT** (`env.LADDER_PROUD` up, `env.STEP_UP`
  down). Rails over a floor are what you haul on; a head under the lip is a pull-up.
- **THE EXIT ASKS THE WALL SIDE FIRST AND MAY NOT BE A LEDGE.** Over a cliff you top out over the lip; inside a
  shaft the stone refuses that side and he steps off inboard. **ON A ROOF THERE IS NO WALL LEFT TO REFUSE IT**,
  so one more stride the same way has to hold him too — that is what keeps him off the merlons.
- **HEIGHT IS A `lift`, NOT A `pos.y`** — the jump's own machinery, so `footPos` and the shadow follow for free
  and a knock-off is `hero.launchFrom` with the climb height. `game.updateClimb` owns his XZ outright (no
  terrain gate, no push-out, like the fog-gate walk), and the phase is driven by DISTANCE climbed.
- **TOPPING OUT IS A HAUL, AND IT IS STILL THE LADDER** (`game.Mantle`, `hero.startMantle`/`poseMantle`). He
  lets go `MANTLE_RISE` under the lip rather than riding the top rungs, and the beat presses and stands him a
  full `LADDER_EXIT` in from the edge. **EVERY GATE THAT LEAVES A BODY ON A LADDER ALONE ASKS `hero.onLadder`,
  NOT `climbing`** — the footing, the terrain gate, the push-out, the lens lift and the INTERACT button, which
  is not one of the things `committed()` refuses and reached a bonfire in the yard through the haul.
- Forward climbs, back climbs down, back + sprint SLIDES; jump or roll lets go. Everything else is refused by
  `committed()`. **NOTHING BUT THE HERO CLIMBS**, so a ladder is an escape from whatever cannot follow.
- `worlds/test_ladder.world` is the bench — two shelves, the watchtower's four flights to its roof, and the
  three runs that must REFUSE to top out. The test beside it prints every head and exit in metres.

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
  you there (`OCCL_IN`, `OCCL_OUT` — out is slower, and `easeShape` takes the speed off both
  ends); it stops being in the way over a BAND not a plane (`OCCL_DEPTH_BAND`); and `OCCL_MAX` counts what is
  in flight, both directions. The shape is a pure function of where the value SITS, never of where a travel
  began — `fadeTo` moves under it every frame the camera does.
- **EVERYTHING THINS EXCEPT WHAT SAYS `solid`** — architecture, cliffs, the water sheet, the bonfire. The flag
  is that way round because as an opt-in every kind added afterwards opted out by silence.
- **GROUND COVER THINS FROM HIS WAIST UP** (`OCCL_TALL`, the rig's SPINE at 0.640·H). `markOccluders`
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
- **EVALUATED EVERY FRAME, NOT ON A CYCLE.** A PRESERVED trigger is held off by `REPEAT_GUARD` —
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

### Mossbeard, the tree smith (`npc.zig`, `props/propforge.zig`)

The third `NpcKind` and the first that is not a man. Owner's brief — wise, old, mustached, a hulking gentle
giant, sad but noble, hammering endlessly on his anvil — and every word of it is a number.

- **THE STROKE IS THE IDLE, NOT A `Gesture`.** A gesture has a clock that ends; he is doing this when you find
  him and when you leave. `Wanderer.hammer` is a repeating phase, `HAMMER_PERIOD`, and `struck` is the
  one-frame edge `game.voiceFolk` spends on `sfx.smith_ring`.
- **THE RISE TAKES FOUR TIMES AS LONG AS THE FALL, AND THE ELBOW CARRIES THE RAISE.** Comptime-pinned, both:
  a shoulder that did the lifting reads as an executioner, and an even rise/fall reads as a woodpecker. The
  head travels 1.96 m — 2.83 m at the top of the raise to 0.88 m on the face.
- **AND IT OVERSHOOTS** (the LAW). `HAMMER_REBOUND` bounces the head 0.19 m back off the anvil and the trunk
  drives past its own stoop with it. There is no hitstop to fake the weight with.
- **THE BEARD ARRIVES LATE.** The moustache is grown onto the burl, so the only thing that can swing it is the
  skull — read off the stroke's phase shifted back by `BEARD_LAG`. A rope that moved WITH the arm is a rope
  nailed to it, and that late arrival is most of what makes the hammer look heavy.
- **BOWED, NOT FOLDED.** `stoop` 25° and `headFwd` 21° put the skull 0.20 m forward of the chest while the
  chest sits 0.075 m forward of the hips. Sad is the head; NOBLE is that the shoulders stay square under it —
  the split is asserted, not described.
- **THE ANVIL IS SOLVED OFF THE STROKE AND NOT THE OTHER WAY ROUND** (`npc.SMITH_ANVIL_Z`,
  `propforge.ANVIL_FACE`). A test re-measures the pair every build, so a re-authored stroke cannot quietly
  start swinging through air.
- **HE STILL HAS TO FIT THROUGH A DOOR.** Crown 2.80 m against the wanderer's 1.77, pinned under
  `propart.TOWER_DOOR_HEAD` — a character nobody can put indoors has one place to stand.
- **THE FORGE YARD IS FOUR PROPS, NOT ONE MESH** (`propforge`): anvil, forge, quench trough, tool rack, laid
  out by an author the way `propmarket` is the caravaneer's.
  - **THE COAL BED IS `Mat.flame`, NEVER `Mat.ember`.** Ember is one of the two VERTEX-ANIMATED ids and is for
    sparks that FLY UP; a static bed under it drifted off the hearth and out of the hood.
  - **THE HOOD STANDS CLEAR OF THE FIRE.** Sat on the hearth at full width it is a KILN that swallows the one
    thing the object exists to show. It is a cone — two goes in boxes left daylight between four slabs and then
    came back as a wedding cake — raised, leaning back, open at the front.
  - **A BIG SMOOTH PROP NEEDS A DARKER ALBEDO THAN A SMALL ONE OF THE SAME MATERIAL.** Shot alone, every piece
    of the first cut came back pale: `art.TIMBER` on a 0.6 m capsule reads at 180 where the same value on a
    fence rail reads at 130. The family carries its own timber and stone, a third under `propart`'s.
  - **AND A 6 mm DISC IS ALWAYS WHITE.** Hammer scale scattered on the floor had every normal straight up into
    the key, so a near-black albedo still landed at full brightness. Ground litter is a `decor` op.

## Sight and leashing

**A LOOK IS A SEGMENT AND IT IS TESTED EXACTLY** (`collision.blocksSight`) — one segment-vs-capsule test per
solid, never a walk of samples. It passes OVER anything whose blocking height is under both ends.

**THE GRID IS WALKED, NOT COPIED** (`env.sees`) — `nearSolids` truncates at `MAX_NEAR`, which over a 20 m line
through a wood quietly drops the wall it was asked about.

**IT IS ASKED ONCE A FRAME, BY THE GAME** (`game.markSight`) for every foe inside `SIGHT_R`, stamped on that
foe's `Leash`. Creatures do not ask it themselves — the prop grid belongs to `env`.

**WHAT IT LOSES IS ITS EYES, NOT ITS MEMORY.** `Leash.blind()` needs `SIGHT_MEMORY` with no line, longer
than `LEASH_CALM`, so breaking sight can never shed a foe faster than walking away does. **A blow outranks
blindness** — `roused()` beats `blind()`.

The leash is one struct every creature embeds:

- **START FAR, STOP NEAR** — turns for home past `foe.leashR(AGGRO_R)`, stops inside `LEASH_HOME_R`. That
  gap IS the debounce.
- **THE TETHER IS THE CREATURE'S OWN NOTICE RING PLUS `LEASH_SLACK`**, not one authored number. A flat
  30 m was also THE SPACING BETWEEN CAMPS, so a tether reached the next encounter.
- **ONLY AFTER `LEASH_CALM` WITH NO BLOW GIVEN OR TAKEN**, and only once the hero has left the patch.
- **THE PATCH IS A PLACE, NOT A SEPARATION** — both ranges in `Leash.tick` are measured FROM THE POST: how far
  the CREATURE has come, and how far the HERO is. Asked as the gap between the two BODIES, tethers nominally
  17–30 m long measured out at 34 m (ogre) to 176 m (leechfly). A test walks the field and pins each one
  (`game.zig`, "NOTHING CHASES FOREVER").
- **A WALK HOME IS NOT BLIND** — step back into the patch, or land one blow, and it turns on the spot.
- **A FIGHT IN PROGRESS OUTRANKS THE TETHER, and that is not a leak**: `noteCombat` is stamped by every blow
  either side lands, so a leechfly that rides him for eighty metres has been FEEDING the whole way. What a
  tether owes there is a prompt let-go once the biting stops — a CLOCK, not a distance.
- **RE-ENGAGING COSTS `REENGAGE_HOLD`** in which it cannot try to leave again.
- **ONE PLAYER BLOW ROUSES IT FROM ANY RANGE for `PROVOKE_ROUSE`** — a COUNTDOWN, not a level, because
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
- **A LADDER TAKES INTERACT AND THEN THE STICK, AND NOTHING ELSE.** Forward is up whichever way the lens points
  — the camera does not steer a ladder — back climbs down, back + sprint SLIDES. Jump or roll lets go of it;
  every other press is refused by `committed()`.
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
  (`LOCK_BLIND_HOLD`).
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
- **AN ARENA IS A ROOM AND THE FOG GATE IS ONLY ITS DOOR** (`worldfmt.Arena`, the `arena:` row, `game.holdInRoom`).
  The ward refuses ONE line 0.8 m thick; on open ground that is a gate you stroll round, and a creature that
  BLINKS never touches the line at all — the duo's magus dissolved 13 m out of its own fight (owner). The row is
  an XZ polygon plus its own `boss=` seal, and it holds every body inside it, HIS included, for exactly as long
  as a name on it still stands. Then it opens, on the same tally and the same frame the gate starts fading
  (`game.solveArenaSeals`, beside `markWards`).
  - **IT IS A PUSH-OUT, NOT THE WARD'S REFUSAL, AND IT IS ASKED ON THE STEP'S START.** There is no segment to
    refuse on a blink, so only being stood back inside answers it; and `Arena.hold` pushes an OUTSIDE point IN,
    so asked about where a body ended up it would reach out and drag a creature walking past into the fight.
  - **THE SEAL IS THE ROOM'S AND THE DOOR HAS ITS OWN COPY**, so the two are PINNED by a test over every shipped
    map rather than trusted to agree — a wall that outlives its door locks you into a fight that is over, and a
    door that outlives its wall is a room you walk out of the back of. The editor closes a room by INHERITING
    the seal off the gate standing in the wall you just drew, and says so loudly when there is no gate on it.
  - **A HAND-DRAWN OUTLINE CAN CROSS ITSELF** (`Arena.simple`) — a figure-of-eight's even-odd test answers
    `false` in its own middle, so it holds nothing exactly where it looks most like a room. Solving one corner
    per 30 deg about a single centre, in bearing order, cannot produce one; a test refuses any shipped map that does.
  - **A BOSS BAR MAY NOT BE GATED ON A RANGE THE CREATURE'S OWN DESIGN EXCEEDS** (`game.sealedInWith`). MEASURED:
    the magus keeps to `MG_KEEP_R` and blinks `MG_REAPPEAR_R` more — 29 m against a bar ring of 26 — and
    `Leash.roused` is a 14 s timer topped up only by being HIT, so chasing the swordsman let it lapse and the bar
    faded out mid-fight. Being SEALED IN with something is the fight whatever the range; `AGGRO_R` went to 30 and
    a comptime block by `MG_REAPPEAR_R` now holds the blink inside the ring for the next creature.
- **A UNIT'S ORDERS ARE STAREDIT'S, AND THEY ARE WALKED NOW** (`wf.FoeAi`, `foe.Post`, `foe.postStep`). JUNKYARD
  DOG is `roam` — roaming about a post, leashed — and `roam_free` is the same dog off its chain; `patrol` walks
  the `wp=` legs out and back; `hold` is what every unit did before this existed, and it is the DEFAULT, so a
  map that never says `ai=` loads unchanged.
  - **THE CREATURE OWES A FIELD AND ONE CALL.** `post: foe.Post`, and `foe.postStep` from its IDLE branch,
    filling the same `movedDist`/`moveSpeed`/`moveYaw` its chase branch fills — a helper that advanced the gait
    itself would run the walk cycle at double speed on exactly the frames the body is walking. Arming is free:
    `resetGroup`/`resetRoles` stamp the authored orders on at spawn, duck-typed.
  - **AND "BACK TO YOUR POST" MEANS THE POST, NOT THE SPAWN PIN** (`foe.homeFor`). Every roamer got three
    metres out and turned round, because a creature's own `.hold` arm compares against where it was placed and
    `LEASH_HOME_R` is a stride: the orders and the go-home rule pulled against each other and the orders lost. The
    same anchor feeds `tickLeash`, or `roam_free` — unleashed BY DEFINITION — is dragged back by the tether.
  - **WHICH UNITS GET THEM IS THE AUTHOR'S CALL, MADE PER UNIT IN THE EDITOR** (owner: let me assign them).
    So every creature that CAN move takes them — 27 of 30 groups — and `hold` being the default is what keeps a
    map that never says `ai=` unchanged. The three that cannot are the FIXTURES, and `game.NO_ORDERS` names them
    with a reason, enforced both ways: a creature added with no `Post` and no line there is an order the editor
    lets you assign that silently does nothing.
  - **AND EACH WALKS IT IN ITS OWN IDIOM.** `foe.postDrive` is the leg-and-gait case (nine of them share it),
    `postAmble` the four that ease a `self.speed`, and `postWant` hands back only the PLACE — which is what a
    hopper leaps to (`frog`, `shroom`), a flyer cruises to (`leechfly`, `blinkbat` — it drifts its round rather
    than blinking it, or the blink has no tell left for the flank), and a quadruped simply walks to instead of
    home (`fungaldeer`, `skitterer`). A round stops at `foe.ARRIVE`: the old ravager's own `HOME_R` was 1.2 against it
    and the body stalled a tenth of a metre short of a mark it could then never reach.
  - **A UNIT UNDER ORDERS READS AS ONE FROM ACROSS THE MAP** — the editor draws its box in the live tone and a
    leashed roamer's tether as a circle, because which bodies have a round is the one thing you cannot see on a
    map full of identical boxes.
- **THE CRIB NAMES EVERY GESTURE, OR THE VERB DOES NOT EXIST** (`editor.CRIBS`, widest-that-fits). It named
  eight and the editor bound twenty-five: undo, redo, cut, copy, paste, select-all, save, delete, grid snap,
  brush size, re-roll and playtest were all live and written NOWHERE on screen. An editing tool whose edit
  verbs are undiscoverable is one you can build in and not revise in.
- **AND NO SILENT CAP MEANS THE AUTHOR CAN SEE IT** (`env.opsCapped`, the editor's status line). The count
  existed and was printed by a TEST — the one person who needs it is the author cranking a belt's count, and
  a budget that bites real content has made the world quietly smaller.
- **A CROSSING IS A GRACE, AND THE CLOCK ON IT IS HIS** (`hero.FOG_GRACE_TAIL`, `hero.startFogGrace`,
  folded into the one `iFramed` the roll already answers). He is untouchable from the sheet to the far side and
  stays that way for as long as he STANDS there; the tail runs only once he is moving under his own power, and
  it is measured off ground SPEED (`FOG_GRACE_STILL`) so it cannot last longer on a slower machine.
  **`updateGateWalk` RE-HOLDS IT EVERY FRAME rather than arming it at the door** — the walk moves him, and a
  grace armed at the door would arrive nearly spent. A death clears it (`respawn`), and a test walks both halves.
- **EVERY BAR THE RUN LEFT ON SCREEN GOES WHILE THE SCREEN IS BLACK** (`game.dropRunHud`) — the death card's
  black, the bonfire's and the map cut's are three doors and all three already re-home the field behind them.
  `bossK` and `spiritK` only tick inside `hud`, which the chrome fade and `rest.active()` both stop calling, so
  they FROZE at full: the rail came back up carrying the dead run's HP and the dead run's chip tail and then
  faded out in front of him, as the black lifted, instead of behind it. The chip statics are hud module scratch
  and need their own `hud.dropBossBars`.
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
  (`hud.beginChrome`/`endChrome`, `game.HUD_FADE_DUR`, read off `hero.deathT` — the clock the YOU DIED
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
- **AN OP MAY NOT SPIN** (`Placer.BUDGET`, `Env.opsCapped` — owner: the editor freezes the PC mid prop-edit,
  "spinning endlessly, almost crashing"). **It was never a leak.** The generator loops were bounded only by
  AUTHORED numbers — `Op.n` is an unbounded `i32` and a `line`'s step only has to clear 1e-4 — and a candidate
  that is REJECTED costs time without ever filling `MAX_PROPS`, so nothing stopped it and nothing showed on
  screen. MEASURED: one line op at 0.001 m spacing over 400 m burns **21 ms a rebuild placing NOTHING**, and
  **227 ms** at the parser's own floor; a rebuild fires `editor.REBUILD_QUIET` after every edit and a map
  holds 20,480 ops. Every generator now spends from a per-op candidate budget: 0.6 ms in both cases, and a belt of
  two million stops at the budget instead of reaching the `MAX_PROPS` panic. **NO SILENT CAP** — `opsCapped`
  counts the ops that hit it, and a test pins that `01_fallen_plain` builds all 16,563 of its props with ZERO
  capped, because a budget that bites real content has made the world quietly smaller.
- **A PANEL MAY NOT SPEND A DRAW CALL PER OP** (`editor.blitMinimap`, `miniGen` — same owner, same freeze).
  `drawMinimap` walked the whole op list and issued one `drawRectangleV` apiece: **16,510 immediate-mode rects a
  frame** on `01_fallen_plain`, and the bill GROWS every time a scatter is exploded into `at:` ops, which is
  exactly what prop-editing does. Every other field on that face already collapsed — `blitField` run-length
  encodes a grid and skips id 0 (the soil and the relief have since gone off the face entirely; the liquid layer
  is its one caller now) — the op layer was the only term that scaled with the map. MEASURED before reaching for a fix: those ops land on 12,442 distinct pixels of the 182x182 face,
  a **1.33x** collapse, so no bucketing makes a per-frame walk cheap and the answer had to be a held texture.
  Painted on `miniGen` (bumped by `bank`, `rebuild` and `touchFolk`) and blitted once.
  - **A HELD FACE IS COPIED BACK, NOT BLENDED BACK.** raylib blends the target's OWN alpha channel by
    `SRC_ALPHA` like the colour, so every translucent thing painted into it drives the target's alpha below 1
    and blending that over the panel multiplies the face a SECOND time — measured, 49/765 darker across 78% of
    it. Blit an opaque face with `rlSetBlendFactors(GL_ONE, GL_ZERO, GL_FUNC_ADD)` under `.custom`.
  - A target has no MSAA and the window does: the held face carries 2,182 distinct colours where the direct
    draw carried 6,538. Same picture, crisper edges — expected, not a regression.
- **THE THIRD FIELD SKIPS TOO** (`env.uploadSoil`). `uploadHeight` and `uploadWater` each compare before they
  rebuild; soil alone re-uploaded three textures and re-ran a 12,544-cell edge dilation on every single edit
  whatever it touched. Cheap beside a terrain rebuild, but it was the odd one out. All three now guard.
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
  `BANK.gain` sets how loud it is. **THE FIGHT IS ONE BAND** — combat rows above `BATTLE_FLOOR` are
  pulled geometrically toward the soft end, halving the spread in dB. Retune by moving the FLOOR, not by pushing
  one row back up; a test pins the ratio and the orderings.
- **THE VOLUME IS RESERVED FOR WHAT IS ABOUT TO HIT YOU.** A creature's committed arrival outranks its own
  movement noise — lunge over hop, slam over step, stab over wingbeat, swing over creak — and the tells sit past
  the midpoint of the band. **TEXTURE GOES AT OR UNDER THE FLOOR**, which takes it out of the band entirely:
  hops, the wingbeat, the idle creak, the whirl. A second test pins both halves, in PAIRS.
- **TEXTURE IS THINNED IN COUNT, NOT JUST IN LEVEL** — `leechfly.DRINK_EVERY`, `rooted.CREAK_EVERY`, and the
  hiss the brood mother no longer spends on laying a sac. The one cadence that MAY NOT be thinned is
  `leechfly.WHINE_EVERY`.
- **THE FAMILY LEVEL IS `TRIM_COMBAT`, NOT THE FLOOR** — the floor moves only the `battle()` band, where
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
  creature's change, not his. No RIPOSTE behind the parry. His arena has a `foggate` on it but no `arena:` row
  yet — the Locations tab's ARENA brush draws one, and the duo's two are the worked examples.
- **Necromancer:** no `necro_*` voice family (borrows the shade's, the wand's and the skeletons'). Nothing
  raises a BODY but this creature, so `foe.rekindle` still has two callers — the ancient priest claws a new
  skitterer out of the ground rather than reanimating anything, and it is the second COLD source.
- **Combat:** no criticals, no guard counter, no AR × motion-value damage (flat constants). Nothing scales a
  cast. Every `FOE_GROUPS` row carries a parry window except the ones `game.NO_PARRY` excuses, and the pairing
  is comptime-enforced both ways, so the count here would only ever go stale: what carries none says why at its
  own impact site (projectiles, ground discs, poured elements — broodlings out on purpose).
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
- **The script layer is foundations only, but it is AUTHORABLE now** (`editor.drawScriptModal`, the top bar's
  Script button beside Objects/World/Sounds). Triggers, their conditions and their actions are made, named,
  re-kinded and thrown away from a modal — and a MODAL rather than a map layer, because a trigger is not a
  place and the one condition that is a rectangle already has Locations to name it. Still hand-written: the
  DIALOG trees themselves (nodes and choices), and the flag/counter/timer TABLES — the modal cycles the names a
  map already declares and cannot coin a new one. Three `NpcKind` (`wanderer`, `merchant`, `smith`). No quest log, no
  journal. `deaths brood_sac` is billed off the brood's own `bursts`.
- **THE EDITOR NOW REACHES EVERY FIELD THE FORMAT HAS.** `Op.r1` on an `at` is the prop's LIFT off the ground
  (`env.Placer.expand`) and has a row; `Op.field` has its "cover field" checkbox; an npc's `dlg=` is a chip per
  conversation the map declares. **AND A MAP SAYS WHERE THE PLAYER STARTS** (`worldfmt.Start`, the `start:`
  row, the World modal, drawn on the map as a ring and a bearing) — hard-coded at (0, 4) facing south, every
  test map had to be built around that one spot whatever its own shape was.
- **EVERY REGION IS SELECTED, MOVED, RESIZED AND NAMED THE SAME WAY** (`editor.Grab`, `pickRegion`,
  `dragRegion`). Zones, locations, clearings and rooms were all create-and-delete only: a rectangle you got
  wrong could only be erased and redrawn, losing its mix or its weather, and a LOCATION could never be renamed
  at all — which made the layer useless for script, since `Cond.region` and every trigger find one BY NAME.
  One union rather than a flag per kind, handles drawn as posts, and the handle under the mouse in the live
  tone. Banked on the first frame a drag moves something, so a plain selection click leaves no undo step.
