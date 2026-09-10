# AGENTS.md — zig-soulslike

Third-person soulslike in **Zig 0.14.1 + raylib** on the sibling `../zig-rts` engine (procedural-mesh `Builder`,
single-sun shadow-map pipeline). README covers what exists. `docs/ELDEN_RING.md` is **PURE Elden Ring** — real
mechanics, nothing about this game. Ours go here, in the README, or in the code.

**KEEP THIS FILE LEAN.** A rule earns a line only if an agent cannot discover it by opening the file it is about
to edit: a law, a contract, a SILENT failure, a prohibition. Not the archaeology of how a number was tuned, not
a restatement of a symbol name. One line each.

Prefer no comments in code. Reuse existing helpers. Don't make product/design decisions — ask. Don't commit,
push or branch unless asked.

## The laws (owner's, non-negotiable)

- **NO HITSTOP. EVER.** No freeze-frames, no time-dilation, no dt zeroing. Weight = shake + rumble + FX + huge anims.
- **NO INPUT READING. EVER.** No creature may branch on the player's inputs or committed actions. A decision reads
  POSITION, BEARING, DISTANCE and ITS OWN CLOCKS — never the hero's state machine.
- **ZERO INPUT LAG.** Stick maps straight to ground speed every frame. Posture blends smooth VISUALS only, ~0.1 s.
- **REACTIONS ARE HUGE**, and **A MASS IN MOTION OVERSHOOTS ITS REST AND SETTLES BACK ONTO IT** — props and
  geometry included. A glide to a stop reads as weightless.
- **FLESH IS ROUND** — `addBlob`/`addCapsule` for organic mass, `addCube`/`addBox` for iron, blade, cloth, masonry.
- **BIG BODIES HINGE AT THE WAIST, LEGS STAY PLANTED** — route lean through SPINE/CHEST (`ogre.PELVIS_SHARE`);
  lean at the ROOT rotates the legs and lurches. Braces take up in the knees.
- **WABI-SABI IS THE HOUSE STYLE FOR ALL ART** — uneven, asymmetric, leaning, gapped, off a seeded `mathx.Rng` so
  builds stay deterministic; cosmetic only. Reads fake ⇒ too REGULAR. **AT THE RIGHT SCALE: BETWEEN the
  instances, not ALONG one** — two tones alternated along a shaft is a barber's pole, the same two separating the
  VARIANTS read as three kinds of wood.
- **NOTHING DEAD IS STRAIGHT, AND NOTHING ENDS IN A POINT** — a dead limb leaves the bole on its axis, rises to an
  elbow, droops off the line to a blunt snap of pale heartwood (`propwood.deadLimbInto`).
- **A ROOT IS DEEP, NOT WIDE, AND NEVER STRAIGHT** (`propwood.rootsInto`) — out of a FLARE, over an arch with
  daylight under it, down to a fat toe and on DOWN; every joint kinked off the bearing with a knuckle at the bend.
- **RELIEF IS SUBTLE** — a few PERCENT of the mass's radius. Sink the proud primitive most of the way in; more
  SIDES beats more relief; judge against the ASSEMBLED thing. Cut AMPLITUDE, never irregularity.
- **CLOTH IS ONE FOLDED SURFACE** (`propart.clothInto`) — rings of `[x,y,z,rx,rz]` in stature-relative units,
  BOTTOM ROW FIRST, every row sharing one set of angular samples. Stacked skirts read as rigid sections.
- **PACKED STONE HAS A CORE** — a row of blocks is only the FACING; overlap past the slot (`propart.courseInto`).
- **DENSITY VARIES** — `env.coverField` scales region density to nothing in clearings and gates the structure
  belts. A flat per-region density is a carpet.
- **A REGION NEEDS THREE LAYERS** — ground-hugger, understorey, canopy. Dead growth is what stops it looking like
  a garden.
- **STRAIGHT CLIFFS, NEVER JAGGED** — the cut is exact and the wall a plane; rock is shapes sunk into it. Any
  per-cell wander is the minecraft look.
- **LIGHT IS NEVER STEPPED** — sun, moon, key, ambient: always a ramp, never an assignment.

## Build & verify

- `zig` is NOT on PATH. `build.cmd` / `build-release.cmd`; toolchain
  `..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe`. `zig build test` runs unit tests.
- **AN ERROR LOOP DOES NOT NEED A BINARY** — `check.cmd` type-checks exe AND test roots in 2.7 s against a 10 s
  build. Loop on it until clean, then build once.
- **Do NOT launch the interactive window** — the owner plays it himself and holds the exe open. `--prefix
  zig-out-dev` when locked.
- **VERIFY WITH MATH WHERE THE CHANGE IS A NUMBER**; shoot only what is genuinely visual-novel. `--shot` (or
  `shot.cmd`) → `shots\` (gitignored). Never claim a *visual* change works without a shot.
- Stages: `--shot-props` (every kind alone + a `COLLIDER` audit line each), `--shot-art` (the whole 2D set on
  contact sheets — a glyph set is judged as a SET), `--shot-land` (terrain/water/caves), `--shot --shot-only
  <substr>` (one stage, 32 s against 3m38s; still SIMULATES everything).
- **A SUBJECT MUST BE LIT, NOT JUST IN FRAME** — `gfx.SUN_DIR` puts the sun over the shoulder at **yaw ≈ 53** and
  into the lens at **≈ 233**; 180–215 shadows a front. A foe turns to face the hero, so photographing its front
  means putting the sensed hero on the SUN's bearing and shooting from ~53.
- **FRAMING IS PART OF THE TEST, AND A FRAMING THAT MUST SURVIVE A RE-AUTHORED MOVE IS SOLVED AND PINNED**
  (`shots.KNIGHT_STRIP`) — boom off the SWEPT BOX of everything the move moves, aim at its middle, let a test
  re-solve; `camera.FOVY`/`game.SCREEN_W`/`SCREEN_H` are public so the solve reads the lens. `follow` does not
  clamp pitch (a small negative pitch at long `dist` buries the eye), the camera ends at `target + back*dist` (so
  interior framings are DERIVED from the room's extent), and the shadow ortho tracks the HERO (so `standHero`
  near the subject). World changes want an overhead at `dist` ~55.
- **WHEN THE SUBJECT IS HOW A BODY HOLDS SOMETHING, SHOOT ALL FOUR SIDES CLOSE** — turn the SUBJECT, not the
  lens, so the sun stays over the camera's shoulder, and solve the boom off what is actually held.
- **A HOLE IN THE WORLD ONLY SHOWS AGAINST A BRIGHT BACKGROUND** — `--bright` drops the sky and clears MAGENTA.
  Count the magenta BELOW the skyline; grass and crenellations are see-through.
- **JUDGE ALBEDO BY SAMPLING THE RENDER** — albedo × 1.72 → linear → gamma 1/2.2, so screen ∝ albedo^(1/2.2) and
  a factor wanted on screen is that factor^2.2 on the albedo. Solve it, `GetPixel` subject AND background, and
  separate on HUE too: everything outdoors here is warm.
- **Thin geometry needs a CROP** — strings, nocked arrows, setts and HUD rims are invisible at 1:1:
  ```powershell
  Add-Type -AssemblyName System.Drawing
  $src=[System.Drawing.Bitmap]::FromFile("$PWD\shots\40_x.png")
  $crop=$src.Clone((New-Object System.Drawing.Rectangle 460,360,300,220), $src.PixelFormat)
  $big=New-Object System.Drawing.Bitmap 900,660; $g=[System.Drawing.Graphics]::FromImage($big)
  $g.InterpolationMode='NearestNeighbor'; $g.DrawImage($crop,0,0,900,660); $big.Save("$PWD\shots\crop.png")
  ```
- **THE SCREENSHOT GOES BEFORE `endDrawing`** (`shots.snap`) — after the swap every capture is last frame. The
  harness CLOSES THE MENU first. PNGs are not byte-deterministic (wind + grain read `rl.getTime`).
- **A TEST MAY ONLY WRITE `worlds/test_*.world`** — `wf.save` panics on any other path under `is_test`.
- **NEVER RUN TWO TEST SUITES AT ONCE** — they share `worlds/` and the save slots; a one-off red is a race. An
  abort (exit 3) TRUNCATES the suite, so a red at the front hides everything behind it.

## Module map

`core/` maths, collision, pose kernel, camera, audio, rumble, bake door · `gfx/` builder, scene, GLSL, element
particles · `world/` terrain, map format, clock, weather, triggers, dialog · `props/` · `foes/` · `play/` hero and
his sheet · `ui/`. Loop, entry, slot and shot harness stay at `src/`. An `@import` is a path from the importing
file; `main.zig`'s test block names each module by that path and `build.zig`'s roster check walks the tree to
enforce it. **How files divide:** minimise TOKENS TO MAKE A CORRECT CHANGE, not file size — a 900-line file whose
contents change together is fine.

| file | what |
| --- | --- |
| `game.zig` | window/loop, input, camera-relative movement, render orchestration, combat beats, YOU DIED |
| `main.zig` · `shots.zig` | entry · the headless `--shot` harness (never in context while working on the loop) |
| `play/hero.zig` | THE HERO — FK skeleton, every animation, swept blade capsule, guard, bow, wand. Start here |
| `core/anim.zig` | THE KEYED-POSE KERNEL — `Ease`/`Key`/`keyAt`, `Spring`/`SpringBank`, `anim.Pose(P)` |
| `core/camera.zig` | orbit rig, ground basis, trauma shake (live-loop only, so `--shot` stays deterministic) |
| `core/collision.zig` · `mathx.zig` | XZ capsule/circle push-out, `blocksSight`, `box` · angles, seeded `Rng`, `gutter`, `turnToward` |
| `core/audio.zig` · `rumble.zig` · `bake.zig` | ~206 synthesized voices through one tape `master` · XInput directly · the one-way door that emitted the first map |
| `gfx/gfx.zig` · `shaders.zig` | `Builder`, scene shader, depth pass, `Sky`, `Vignette`, `Mat` · every line of GLSL and nothing else |
| `gfx/elemfx.zig` · `particleart.zig` | one signature per `combat.Elem` · one seeded mote atlas, four variants per style |
| `world/env.zig` | THE WORLD — terrain, op replay, `coverField`, uniform grid, cullers, occluder fade, lights |
| `world/worldfmt.zig` | THE MAP FORMAT — ops, zone/foe/npc/trigger/dialog tables, one comptime field table |
| `world/daynight.zig` · `weather.zig` | sun/moon path, the hour's palette, the anchor hour · rain, mist, embers, bird skeins |
| `world/caves.zig` · `spar.zig` | a second surface UNDER the heightfield · F6, one walled room and one creature |
| `world/trigger.zig` · `dialog.zig` | SC1's conditions + actions, switches/counters/timers · one conversation, node walk + panel |
| `props/props.zig` | prop vocabulary + `INFO`; `displayName`/`group`/`biome` exhaustive; `decks`/`stack`/`climb` |
| `props/prop*.zig` | meshes by family — `propart` (palette + weathering), `ruins`, `gold`, `build`, `village`, `market`, `forge`, `rock`, `wood`, `flora`, `fungus`, `coral`, `ash`, `bone`, `ember`, `palace`+`desert`, `fx` |
| `foes/foe.zig` | THE FOE STANDARD — contract, `Blade`/`strike`/`Blow`, particles, `Leash`, `Nav`, `Post`, `grip` |
| `foes/foestat.zig` · `behave.zig` | one stat multiplier per kind · `Routine` + named scripts (`DISENGAGE`/`FLANK`/`KITE`) |
| `foes/npc.zig` | THE FOLK on the hero's scaffold — wanderer, caravaneer, MOSSBEARD (whose idle IS a hammer stroke) |
| `foes/knight.zig` | BONE KNIGHT — first boss, 900 HP, tower shield, `Gas`. **The AI template for every other foe** |
| `foes/fungalduo.zig` · `druidess.zig` | bosses two and three — abutting bands, two bars · keepaway caster, vines, three healing breaks |
| `foes/ogre.zig` | 24 bones, high poise, never strafes; `TURN_RATE` is the class the knight is pinned into |
| `foes/warrior.zig` · `archer.zig` | shieldman (blocks, guard-breaks) + greatsword (hyper armour) · kite-only; owns `Shot` (arrows, bolts, rock) |
| `foes/kobold.zig` · `fishman.zig` | the two warbands — a priest is why they are one group · held together by a NET |
| `foes/brood.zig` · `shroom.zig` · `shroommage.zig` | mother/sacs/broodlings, venom POOLS · flings itself, poison cloud · the fireball BOUNCES |
| `foes/shade.zig` · `blinkbat.zig` | legless, drains FOCUS, the one thing that TELEPORTS · blinks onto your flank, bites once, blinks out |
| `foes/delver.zig` · `necro.zig` | goes UNDER, bursts or ploughs, lobs a rock · holds a corpse open and raises it once; only COLD source |
| `foes/leechfly.zig` | first FLYER; never lands, drinks HP, zooms out of sword reach |
| `foes/wolf.zig` | first SPIRIT, what the BELL calls. NOT a foe; first QUADRUPED, 27 bones |
| `foes/frog.zig` · `fenlurker.zig` | the two waterfaring bodies — sunk, the lurker is unreachable; the counter is DRY LAND, and a 4.96 m TONGUE is what closed the free water in between |
| `foes/rooted.zig` · `slumberbloom.zig` | the FIXTURES — never move; the bloom has no blow at all and is the only SLEEP source |
| `foes/fungaldeer.zig` · `mastodon.zig` · `rotgorger.zig` | the quadrupeds — flower is ARTILLERY · elephant gaits only, 2.35 m withers · EATS THE DEAD, kin included |
| `foes/skitterer.zig` · `ancientpriest.zig` | walks ON ITS RIBS, shy of flame · never melees, claws a skitterer out of bare earth |
| `foes/hollow.zig` · `owlbear.zig` · `mimic.zig` | second lock point (a 20 HP rider) · FIRST CONSTRUCT, stone until DARK · a CHEST until pressed or hit |
| `foes/sporegolem.zig` · `cinderwake.zig` · `birchwight.zig` · `salthusk.zig` | `ARMOUR` is the creature · hazard laid by its own feet · caught, it escalates · its KILL is the dangerous part |
| `foes/ent.zig` | THE CORRUPT ENT — 4.6 m on the SHARED scaffold; a bough sweep with NO inner hole, a return off the far hand, and an acorn volley whose FIRST nut is aimed exactly at him. FIRE is the answer (`-60`) |
| `play/combat.zig` | `Vitals`, `Stamina`, `Focus`, `Regen`, guard rules, `Elem`/`Resists`, `Status`, `Quick`, `Memory`. **Retune feel here** |
| `play/stats.zig` · `passivetree.zig` | seven attributes, bar curves, the ONE skill curve · PoE2's tree radially, `Bonus`, the wheel |
| `play/item.zig` | item vocabulary, `Use`, **`Equip`/`Wear` (the GEAR table)**, `Bag` |
| `play/liquid.zig` · `drops.zig` | one `Soak` row per `wf.Liquid` · one drop row per `FoeKind`; **the one thing LUCK reads** |
| `play/rest.zig` · `souls.zig` · `chest.zig` · `pickup.zig` · `award.zig` | bonfire/campfire · the drop and the walk back · boxes off `Op.loot` · the glow a drop stands as · the first-time card |
| `play/counter.zig` · `tune.zig` | shop and smithy as one `Trade`, headless · THE STATS BENCH; `tuning.cfg` is the DIFFERENCE |
| `ui/hud.zig` | ER HUD, pad glyphs, day dial, boss bars, and **the ONLY path to draw or measure text** |
| `ui/uiart.zig` · `ui.zig` · `icons.zig` | chrome dressing shared by hud/menu/book · editor widget kit · editor glyphs from primitives |
| `ui/book.zig` · `itemart.zig` | THE CHARACTER BOOK — doll, bag, sheet, MAP page · pictures of things, sized by the caller |
| `ui/mapart.zig` | THE WORLD FROM STRAIGHT UP — one classification, `Lens`, `Seen`. Minimap and MAP page are its two faces |
| `ui/menu.zig` · `counterui.zig` | boot screen, pause/debug, retro rack · the counter's panel, the DIALOG's shape |
| `ui/editor.zig` · `tuneui.zig` · `objview.zig` | THE EDITOR, layered StarEdit-style; biggest file, next split candidate · the bench's face · object viewer, JUKEBOX, FX BENCH, **and `charRuler`, which stands the hero beside a body at his own 1.8 m** |
| `save.zig` | THE SLOTS — three files in the map's own `key: value` grammar, each with its picture |

- **A NUMBER THE BENCH CAN MOVE IS A `var`, AND ITS BANK IS THE `const` BESIDE IT** (`play/tune.zig`). Anything
  that read a table AT COMPTIME must be pointed at the bank (`combat.ailBank`, `item.equipBank`, `priceBank`,
  `combat.bankRow`), and a creature's ring is ASKED for rather than copied (`game.aggroRing`). Identity — a name,
  a socket, which scroll a spell is on — reads the bank on purpose.
- **A DEFAULTED FIELD ON `Game` OR `Env` MUST BE ASSIGNED IN `init`.** Both are `alloc.create`d, so `= .{}` never
  runs and the field comes up as the fill byte. Silent; it has bitten three times (`pack.n`, the whole day/night
  cycle dead off an unassigned `g.day`, and every `Env` counter `build` reads before the props exist).
- **THE LIVE PORTRAIT IS TWO CALLS AND THE SPLIT IS LOAD-BEARING** (`hud.renderPortrait`/`blitPortrait`) —
  `endTextureMode` restores the DEFAULT framebuffer, not the target bound before it, so a render nested inside
  `beginChrome`'s target sends the rest of the frame at the backbuffer. **Render BEFORE the chrome, blit inside.**
- **`elemfx`'s SIGNATURE IS THE MOTION** — fire RISES and leaves a residue, cold FALLS and lies about (longest
  life by 2×), lightning DOES NOT TRAVEL (shortest by 3×, the only colourless one), chaos goes INWARD. Tests tell
  the four apart with colour taken away, and again on hue alone.

## The hero rig (`hero.zig`) — and every humanoid on it

- **Matrix convention (critical):** raylib `MatrixMultiply(a, b)` applies **a FIRST, then b**. Local =
  `mul(animRot, translate(offset))`, world = `mul(local, parentWorld)`. Backwards and the skeleton explodes.
- **18 bones** (`hero.N` — 17 joints plus the HELD weapon on the right wrist). `pose()` chains one world matrix
  per bone ONCE per frame and `draw()` only replays them, so shadow and silhouette always match.
- **Anatomy and gaits are real** (Drillis & Contini; Perry/Winter walk, Novacheck run) and **phase is driven by
  DISTANCE travelled, never time**, so feet never skate.
- **THE 18-BONE SCAFFOLD IS SHARED** (`restHumanoid(hx, sx, stature)`) — do not transcribe the joint layout into a
  new creature; only `hx`/`sx` and stature are honestly per-creature. **HUMANOID FOES REUSE THE HERO'S WALK**
  (`advanceGait` + `legChain`): never author a bespoke walk, only the upper body is per-enemy, and a foe rig must
  keep the hero's leg indices 5..10 where they are.
- **A SCALE≠1 HUMANOID MUST SCALE ITS PELVIS HEIGHT** (`pelvY*fs`) or the legs sink.
- **A CYLINDER IS CAPLESS, INCLUDING ON THE HERO** — a ball at each hip and knee seals the mouth and reads as the
  joint, inside the belt's own half-width so no standing silhouette changes.
- **FEET DO NOT SINK: LEVEL THE ANKLE, NEVER LIFT THE BODY** (`legChain` measures the deepest sole corner against
  its `SolePatch`). Check the mesh too: `addCube` takes a FULL size, `addCapsule`/`addBlob` true RADII.
- **THE UPPER BODY MUST ARTICULATE TOO — legs alone are not a gait.** Every walking humanoid owes a contralateral
  arm swing at full amplitude, elbows flexing through the forward half only, a shoulder girdle counter-rotating
  against the pelvis, a trunk nod twice a stride, and a head that counter-rolls it. **Stagger the LAGS** — joints
  peaking on one frame read as a welded block. `ogre.poseUpper` is the worked example.
- **AN ELBOW BENDS ONE WAY, AND THAT WAY IS `rx(NEGATIVE)`.** Either a positive constant is negated at the joint
  or it is authored negative and passed raw — **never both**, which is how it broke three times (the folk waved
  behind their own backs; every `ancientpriest` posture; all eight of `necro`'s `*_EL`). Gesture DELTAS carry the
  sign too, and each file pins its own signs in a test. **A POSE AUTHORED AROUND THE BUG DOES NOT SURVIVE THE
  FIX**: `staffFit` counter-rotates exactly, so the ANGLE never moves and the HEIGHT does.
- **AN ATTACK IS KEY POSES CHASED BY SPRINGS, NEVER TWO CONSTANTS AND A LERP** (`anim.Key`/`keyAt`/`Spring`/
  `SpringBank`; Overgrowth's model). A→B has nowhere to put a gather, a hang, a snap, a follow-through or a
  recoil, so it reads STIFF however it is tuned. **No dial fixes that.**
  - **THE POSE IS A TARGET, NOT THE OUTPUT** — a spring moves by velocity, so it cannot jump however far its
    target does, which makes every interrupt continuous for free and retires hand-rolled cross-fades.
  - **THE CHAIN LAG IS THE BANK'S, NOT THE MOVE'S** — each channel pulled a little less hard than the one before
    so mass flows root→tip. **The channel array's ORDER is load-bearing.**
  - **SEAT THE SPRINGS AT SPAWN** (`SpringBank.seat`) — a bank comes up at 0, and 0 is a real pose: arms down.
    **ANY chased channel has to be seated** wherever a move is dropped in from nothing (debug entry, shot, test).
  - **`.hold` IS HOW A BAIT IS WRITTEN** — a delayed downswing whose pose creeps reads as the swing starting.
  - **AN ARRIVAL IS `.accel` INTO THE BLOW AND `.decel` OUT OF IT, NEVER `.snap`** — `snap` is front-loaded and
    puts the whole stroke BEHIND the capsule (the dagger crossed 13° of its 84° arc inside its own live window).
  - **THE HERO'S OWN POSES TAKE NO `dt` AND SO HAVE NO SPRING BANK** — every hero pose is pure in its own clock,
    which is what keeps `--shot` reproducible, so load, hang, snap, carry-past and settle are authored as KEYS.
- **EITHER HAND MAY HOLD ANYTHING, AND THAT IS THREE THINGS PER ARMAMENT** — the MESH, the POSE of the arm, and
  every WORLD POINT taken off it. All three ask one question (`handsHold`/`meleeLeft`/`wandLeft`/`shieldLeft`/
  `torchLeft`/`bellLeft`) and a pose picks its side through `armSide(left, authoredLeft)`, whose `mirror`
  multiplies the LATERAL channels and leaves sagittal `rx` alone. **Miss the third and it fails INVISIBLY** — a
  rod equipped right drew and carried perfectly and threw every bolt out of the empty left fist. **A TWO-HANDER
  CLAIMS BOTH HANDS FROM EITHER SLOT**: ask "is the RIGHT slot two-handed", or a bow in the left leaves a shield
  in the right blocking and parrying.
- **THE WEAPON HAND IS ONE HAND** (`handsHold`, `offInHand`) — the rig has ONE held bone, so two live melee cells
  would draw one nowhere. The RIGHT cell wins, and `offInHand` says so in words the book can print.
- **THREE SHAPES ON ONE GRIP** (`hero.Blade`, `bladeOf`) — dirk and club are the SWORD bone with another mesh and
  capsule, so pose, trail, sparks and every window are written once, LATCHED at `startAttack` with the row.
- **ON THE LEFT ARM A POSITIVE ABDUCTION CHANNEL FOLDS IT ACROSS THE CHEST**, so "out to his left" is negative.
- **A DRAGGING HEM IS NOT A BONE** — it rides the ROOT through a lag matrix, and it is a SPRING not an ease: the
  lean opposes the travel, OVERSHOOTS and settles. Hand-rolled `1 - EASE*dt` damping goes NEGATIVE past 154 ms a
  frame; use `anim.Spring`.
- **A POLE IS ONE PATH AND EVERYTHING IS MEASURED OFF IT** (`staffPath`) — mesh, grip calibration and `staffSeg`
  read the same deterministic curve, stepping by ARC not by height, or a bent 2.00 m pole comes out longer than
  2.00 m of wood. It turns about the GRIP, not the bone origin (the wrist sits 0.09·H above the palm).
  `staffTilt`/`wpnTilt` are **180-IS-PLUMB**, and **THE FIT BILLS THE ARM BUT NOT THE TRUNK**, so a pose that
  arches the spine, throws the trunk or drops the grip pays at its own constant — unbilled, the planted pole
  swings out flat or its ferrule goes through the turf. **A KIT AUTHORED POINTING UP OFF THE GRIP IS TURNED BY
  `hero.staffFit`**, and the ARM'S OWN FLEX comes out of the tilt; fitted in the forearm's frame instead, a level
  `tilt` put a point 3.73 m up over a 1.71 m hero.
- **THE CROSSING SIDESTEP IS GEOMETRY, NOT TUNED ANGLES** — one symmetric ±`STRAFE_ABD` sweep per leg, half a
  cycle apart, planted foot WORLD-FIXED. Ask for foot heights and solve for the knee.
- **THE DEAD COLLAPSE DROPS THE PELVIS FASTER THAN `deadLegs` FOLDS THE LEGS** — soles finish ~1.0 m × scale under
  the turf on every humanoid sharing `heromod.deadLegs`. Recorded, not patched: lifting the rig onto the floor
  keeps the body STANDING while it sinks, which is worse.
- **`item.Wear` IS APPEND-ONLY, AND THAT IS NOT ENOUGH ON ITS OWN** — a save's `worn:` run is positional over that
  enum, so the KIND names its own socket and the position is only a cursor.

**Animation art direction.** IDLE: upright, still, alive — a slow breathing bob only. WALK: unhurried, grounded,
near-upright (~3°), RESTRAINED arms (never both forearms out front — the "zombie arms" fail), low hip sway, clear
heel→toe, slight toe-out. RUN: low and aggressive, deep lean over a crouched pelvis, arms pumping at ~90° (not
swept-back "naruto" arms), real flight phase. SPRINT is the run dialled up — falling forward and catching it.
ROLL: dive into a tuck, ONE somersault over ONE shoulder about a low ball centre, then a spin-free rise; no float.
Blends: idle↔walk by a `moving` ease, walk↔run↔sprint by ground speed, discontinuities cross-fade ~0.09 s.
**Stances never snap while mechanics stay instant.** REST: he PLAYS the guitar he is holding — one frame shared by
mesh and pose, both arms SOLVED onto it by two-bone IK keeping bone lengths (`hero.armTo`), and the test measures
pick against strings and fingers against neck.

## Adding a foe (`foe.zig`)

- **Satisfy the contract:** `pos`, an embedded `combat.Vitals` (`vit`), `hits`, `justDied`, and the accessors
  `alive`/`dying`/`staggered`/`airborne`/`bodyR`/`hurtRadius`/`centerWorld`/`lockPoint`/`topWorld`/`flashFrac` +
  `tryHit(foe.Blade)`. Build vitals with `Vitals.initFoe`, never `init` — that is the slow foe regen schedule.
- **`tryHit` IS TWO SHARED CALLS THEN WHAT IS YOURS** — `foe.reached(self, blade) orelse return` (swept test,
  one-hit latch, anti-cheese rouse, the facing snap a `pierce` earns) then `foe.wounded(self, s, blade, ...)`
  (hit count, flash, shove — returning whether the BLOW was heavy, which is what blood and chips are sized off,
  never the REACTION). Damage and the reaction live in `foe.strike` under `reached`.
- **Shared points:** `foe.bodyPoint` for a height on the creature's own axis, `foe.markOn` for the reticle (which
  rides the POSE), `foe.stunCurve` for the one reaction shape in the game.
- **Group + register.** A `Group` exposes `anyDied`/`totalHits`/`aliveCount`, and its `reset` and `draw` are
  ONE-LINE DELEGATES to `foe.resetGroup`/`drawGroup` — the draw's `setFlash(0)` tail is what a fourth copy would
  forget. A multi-kind group has `kind = null` and each member exposes `kind()`; a group with anything else on the
  field exposes `clear()`.
- **CROSS-CUTTING STATE IS EMBEDDED BY THE CREATURE AND STAMPED BY THE GAME** — eyes (`Leash`), feet
  (`combat.Root`), the hour (`foe.Win`), flame (`foe.Glare`), the room (`room`, `foe.Ground`), orders
  (`foe.Post`), sight, parry (`foe.Parry`), steering (`foe.Nav`). **The creature reads the field; it never reaches
  out for the state.** Every one is folded over `FOE_GROUPS` and keyed off `@hasField`/`@hasDecl`, so gaining one
  is a field and a method and never an edit there — **and a test pins field ⟺ method, because both halves fail
  SILENTLY.**
- **WHAT A CREATURE IS AND HOW IT TRAVELS ARE TWO AXES AND ONE TABLE** (`Nature`, `Gait`, `traitsOf` — exhaustive,
  so a creature cannot be added unclassified). `Gait` is what the water gate reads. **`Gait.flying` IS NOT
  `airborne()`** — that one is whether a body is off the ground THIS FRAME, and it is what collision asks.
- **Anything the map can post is a `wf.FoeKind`, APPENDED never inserted** (editor unit brushes are pinned to that
  enum's order at comptime), plus `foeName`, a `unitTips` line, a `unitIcons` glyph and a `foeSwatch`. Several
  kinds of one creature go in as a CONTIGUOUS RUN, pinned at comptime.

**Billing a blow.**

- **A BLOW IS BILLED FROM ITS IMPACT, NOT THE STRIKE'S FIRST FRAME.** At `s = 0` the limb is still where the wind
  left it; `*_IMPACT_K` (0.25 for the mastodon's tail to 0.85 for the ogre's slam) is what `toImpact` hands the
  parry window AND where the `try*` gate opens. **THE ORDINARY SWING'S SHARE IS ONE NUMBER** —
  `foe.MELEE_IMPACT_K`, which the seven `catchMelee` families and `rooted` alias rather than restate. A stroke
  judged off a SWEPT SEGMENT (`weaponReaches`) is exempt: it bills when the edge actually crosses him.
- **A FRONTAL ANIMATION BILLS A FRONTAL CONE** (`foe.inFront` + a `*_FRONT_DOT`), never a radius. Only a RING — a
  shockwave, a burst, a thrown rock — is 360°.
- **A RANGE GATE IS MEASURED FROM THE TARGET'S HIDE, NEVER ITS CENTRE** (add `HERO_REACH`, or the quarry's
  `bodyR`) — `env.resolveActor` holds an attacker `bodyR + its own` out, so a flat centre-to-centre range is
  unsatisfiable on anything broad. **HEIGHT IS A SEPARATE QUESTION FROM REACH and needs its own test**: ask for
  CHEST height (1.12 m), not "below his crown", which passes on a blow that only touches hair.
- **MELEE REACH IS REFUSED ACROSS A DROP** (`REACH_RISE`, 2 m of GROUND between the two, both ways). Arrows and
  blasts fly their own path and are not gated.
- **A BAND HELD AT A CONSTANT WHILE ITS HURT BOX SCALES ONLY AGREES AT ONE SCALE** (`foe.triggerBand`) — the
  editor posts a body anywhere in `FOE_SCALE_LO`..`HI` and `hurtReach` tracks it, so a `classify` comparing
  against the authored world metre commits to a blow that cannot land and, having chosen a strike over a step,
  never closes. Where the band IS the bill's own constant, compare against `hurtReach` directly. **AND THE NEAR
  EDGE IS THE SAME LIMB**: a `minR` left at the authored metre while `maxR` scales INVERTS the band at
  `FOE_SCALE_LO`, and a FIXTURE cannot walk out of the ring that leaves — so a test sweeps LO/1/HI, not 1 alone,
  and a STAND-OFF rides the band as a SHARE.

**Poise, flinch and death.**

- **A CREATURE'S FLINCH IS HEALTH TAKEN IN BLOWS OVER A PERIOD, NOT A COUNT OF BLOWS** — `Vitals.strike` pours
  `FOE_POISE_PER_DMG` (0.82) of every point a HIT takes into the poise pool and a blow's own `poise` is ignored;
  a drip pours nothing. `poiseMax` IS the damage a creature shrugs off inside the refill window. The HERO's
  stagger keeps the blow's `poise` — the WEIGHT of what hit him. **A BLOW THAT REFUSES THE FLINCH MUST HAND THE
  POOL BACK**, since stripping the blow's `poise` no longer does anything.
- **NOTHING BUILDS ON A BODY ALREADY STUNNED** — neither pool, not the lightning meter. The stagger is the punish
  window it earned. **YOU CANNOT DO ONE THING OVER AND OVER**: each flinch, break and status proc leaves WEAR on
  that channel (`lightWear`/`heavyWear`/`ailWear`), the next taking (1 + wear × 0.6/0.6/0.7) as much and halving
  every `WEAR_HALFLIFE`. **Creatures only — bosses do not get to learn him.**
- **`justDied` IS A ONE-FRAME FLAG** — reset at the TOP of `update`, set in `enterDeath`, apply the blade at the
  END. Applied externally without the reset it latches a nonstop rumble/shake.
- **EVERY BODY GOES OUT THE SAME WAY** (`foe.dissipate` + `Dissolve`) — the DURATIONS and the `Dissolve` are
  per-creature, the SHAPE is not, and it reads FIELDS only, which is what lets it live in `foe.zig`. **The SHADE
  is the one exemption.** **A BODY GOES BY GOING TRANSPARENT, NOT BY GETTING SMALL** — `rigScale` is a tenth and
  the vanish is an ALPHA through `Scene.beginFade` (depth-mask off), **VIEW PASS ONLY**: the depth pass has no
  fade uniform, so a body keeps its shadow while any of it is left.
- **A CORPSE IS NOT A COLLIDER** — `alive()` stays true through collapse, so every collision site asks
  `foe.corporeal`. **…BUT A BODY ON THE GROUND IS A CAPSULE, NOT THE RING AT ITS FEET** (`game.bodyOf`): a
  creature that can lie down answers `bodySeg`, off its posed SKULL, and `pushOut` on a degenerate segment IS
  `pushOutCircle`.
- **A BODY ALREADY ON THE GROUND CANNOT BE FLINCHED UPRIGHT** (`floored`) — damage, flash, chips and stance still
  land, only the state change is refused. Death goes through.
- **ONE CHANNEL SAYS WHERE A TOPPLING BODY IS** (`toppleAmt`/`rollAmt`, 0 standing, 1 flat, NEGATIVE forward) —
  topple rotates the ROOT about the ground between the feet, roll is `ry(180)` inside the rig, and `turnAbout`
  exploits `Ry(180)·Rx(θ) == Rx(−θ)·Ry(180)` so the swap is invisible on the frame it happens. **SO EVERY WORLD
  POINT COMES OFF A POSED BONE** — a height off the feet would hang in the air over a body on the ground. **A
  ROCK ON THE BACK RIDES THE SAME CHANNEL THE ROLLOVER TURNS**: a body cannot rock about one axis and turn about
  another and read as one mass.
- **A FALL IS QUADRATIC, THEN OVERSHOOTS AND SETTLES**, and the body ARRIVING is an EVENT: dust, brake, a voice on
  that instant. **A FELLED STATUE DOES NOT CURL.**
- **A BODY ON THE GROUND IS LOOKED AT, NOT STOOD OVER, AND IT IS NOT HIDING** — `blocksSight` takes the LOWER of
  its two ends, so a fallen mark is stopped by knee-high rubble (`foeStaggered` holds the lock through the punish
  window it just bought); and the mark is floored at the HERO shoulder for the PITCH only, so the reticle still
  rides the body.
- **A BODY THE NECROMANCER CAN USE IS A `raisable`/`reraise` PAIR AND A `heldOpen` FIELD** — nothing else, and no
  edit to `game.markVigil`/`applyRaises`. The field is named for what it does to the BODY, not for the caster.

**Deciding a move.**

- **A MOVE IS JUDGED BY THROWING IT, NOT BY LOOKING AT IT.** Every blow goes through the REAL `update` at a hero
  stood across its OWN band — gather aiming, strike tracking and stepping, the man shoved out to
  `closestApproach` as `env.resolveActor` would — and must bill a hit at every stand. `knight` and `ogre` carry
  the worked tests. **A strip or a shot is not the judge.**
- **REACH IS MEASURED DOWN THE FACING, WHILE LIVE, THROUGH THE REAL UPDATE** — never at the bearing the kit flies
  furthest (a gather aims the body square, so a flank number is a distance nobody stands at), never before the
  impact frame (that is picture, not reach), never off a keyed replay (springs lag the keys by a few frames).
- **A BEARING THE KIT CANNOT BE BROUGHT ROUND TO IS A HARD GATE AT THE CHOOSE**, never a lower score — a whiff is
  not a worse option, it is not an option. **The gate is SOLVED off what the wind can actually turn** (the
  rear-back's share of `TURN_RATE` over its own duration, plus what the kit subtends at that stand), so retuning
  either end cannot leave it behind. **Off the gate a body LOOMS** — `.wait` is `enterIdle` and idle faces the
  quarry at the FULL rate: a gate is only a hole if the state it falls through does nothing.
- **A MOVE THAT CANNOT LAND IS NOT A DECISION** — a choose site tests the move's OWN band, not just its outer
  range. The ogre's swipe passes clean outside anything hugging its legs while collision holds the hero inside it.
- **A STROKE HAS AN INNER EDGE TOO** (`reachIn`, `nearR`) — a scorer skips a stroke whose dead zone or far edge
  holds the man. **AND A LUNGE ONLY COUNTS AS FAR AS IT HAS LANDED WHEN THE KIT CROSSES THE FRONT**
  (`stepLands`); the rest of the lunge is reach the far stand never saw.
- **HOW HARD A STROKE FOLLOWS YOU IS A PROPERTY OF THE STROKE** (`Attack.track`), not one global rate — HEAVY rows
  stay under `TURN_RATE`, because commitment has to cost tracking or there is no window. **A STROKE THAT CANNOT
  FOLLOW YOU CARRIES THE BODY AT YOU** (`Attack.step`). **AND A SWING IS ONLY AS ACCURATE AS THE THING ON THE END
  IS WIDE**: a swing-bearing allowance may never exceed the kit's own subtended half-angle.
- **A COMMITTED LINE IS COMMITTED AT THE LAUNCH** — a charge's wind may aim past the turn rate, because what you
  dodge there is the travel, and the travel then steers not at all.
- **DENYING MOVEMENT IS A POST-STEP GATE, NOT A GUARD AT EACH MOVER** (`foe.grip` + `defer grip.hold`,
  `game.gateTerrain`) — taken once at the end of `update`, because a creature grows movements and a per-site list
  is a list to forget one from. It takes ONE thing, the feet: the state machine still runs, the kit still swings,
  blows still land. Y is left alone (`game.groundActor` owns it).
- **A JUMP IS THE ONE THING THE GRIP REFUSES OUTRIGHT** (`foe.canLeap`) — a leap does not TRAVEL, it leaves the
  earth, so it is gated where the move is CHOSEN, asked of the move's own `hop` and never of one move by name.
  Already airborne when the grip closes, it finishes its arc; re-ask at the launch if a root can close during the
  wind. **A TELEPORT IS A JUMP TOO**, and it is the one move that must not fire out of a STAGGER: a creature that
  vanishes mid-flinch erases the punish window, so the blow sets a latch and the blink is spent at the next choose.
- **STEERING ROUND WHAT IS IN THE WAY IS `foe.Nav`** — a `nav` field and ONE method, `navWant(target)`. It is
  STEERING, not a route: no graph, nothing remembered, a heading tested for the next couple of metres against
  `walkStep`/`resolveActor`, fan tried NEAREST-FIRST. Read in ONE place: `Nav.aim` for a body that walks where it
  LOOKS, `Nav.along` for one stepping on a committed vector with its eyes on him; a hop is bent at the CHOOSE.
  **ONLY THE TRAVEL STATE** — swing, wind, lunge, leap and pounce are committed, and **the attack hop is left
  straight on purpose.** A FLYER is never steered. Asked about whoever the creature is FIGHTING (`Threat.aim`).
- **A UNIT'S ORDERS ARE STAREDIT'S** (`wf.FoeAi`, `foe.Post`, `postStep`) — JUNKYARD DOG is `roam` (about a post,
  leashed), `roam_free` the same dog off its chain, `patrol` walks the `wp=` legs out and back, and `hold` is the
  DEFAULT so a map that never says `ai=` loads unchanged.
  - **The creature owes a field and ONE call** — `postStep` from its IDLE branch, filling the same
    `movedDist`/`moveSpeed`/`moveYaw` its chase branch fills. A helper that advanced the gait itself would run the
    walk cycle at double speed on exactly the frames the body is walking.
  - **"BACK TO YOUR POST" MEANS THE POST, NOT THE SPAWN PIN** (`tetherFor`, `homeFor`) — the same anchor feeds
    `tickLeash` at every call site, or `roam_free`, unleashed by definition, is dragged back by its own tether.
  - `postDrive` is the leg-and-gait case, `postAmble` eases a `self.speed` and steps by the speed REACHED (`accel`
    shapes the gait blend and moves no mass), `postWant` hands back only the PLACE. A round stops at `foe.ARRIVE`.
  - **The three FIXTURES that cannot move are named with a reason in `game.NO_ORDERS`, enforced both ways** — an
    order the editor lets you assign that silently does nothing is the failure.
- **A BODY MAY OFFER MORE THAN ONE LOCK POINT** — `lockParts()`/`lockPointAt(i)`, found by `@hasDecl`; part 0 is
  `lockPoint`. **A PART IS A SPHERE TESTED BEFORE THE BODY'S, ON THE BODY'S OWN SWING LATCH** (`reachedPart`) so
  one swing lands on the head or the chest, never both. `poiseK` scales the poise pour alone, and the pool it goes
  into is whoever's the caller hands over. A point that GOES is a count that drops, and the lock falls back onto
  the body that carried it.
- **Foe pacing:** the archer's BACKSTEP is a committed jump straight back, inside sword reach, on a 7 s cooldown —
  it buys the shot back exactly once. **An evade you can spam is a wall.**

### The bosses

**BONE KNIGHT** (`knight.zig`) — Anor Londo Sentinel (`docs/GIANT_KNIGHTS.md`) on the ER knight brain
(`ELDEN_RING.md` §7), 900 HP. **The AI template: read this file before authoring any other creature's brain.**
What transfers:

- **HE IS LEARNED, NOT ROLLED — AND THAT TEST IS THE DESIGN.** Attack choice is POSITIONALLY DETERMINISTIC: each
  band-and-side has an ORDERED PATTERN a `cursor` walks, a move on cooldown is SKIPPED rather than waited for,
  and `classify` is pure over one `Sit` so a test pins that the same place twice gives the same answer. **The
  variety comes from the player's own feet.** **INSIDE A BAND HE WEIGHS, HE DOES NOT WALK A LIST.**
- **A COMBO IS A FIXED ROUTE HE WALKS** (`routeFor`) — cut short only by the player LEAVING; nothing follows the
  OVERHEAD, so a route may only reach it LAST. **HE IS NOT MASHED OUT OF A STRING HE HAS STARTED**: mid-route the
  light flinch is refused, the OPENER is interruptible, a STANCE BREAK always stops him.
- **THE ANIMATION CONTRACT IS FIVE PHASES** — opening pose → signal → a strike of almost no time → **held End
  Pose** → return. Every move is a KEY LIST per phase and the End Pose is gained by writing no further key (the
  track clamps). Tests pin the seams (`wind[1.0] == strike[0.0]`) and that every stroke HAS a shape.
- **EVERY STROKE LANDS ON THE MAN WHERE HE STANDS** — arcs authored LOW and THROUGH THE FRONT, and **EVERY GATHER
  ENDS IN A HANG.**
- **THE WINDOW IS THE COMMIT — NOT THE FLANK.** You cannot out-circle him on foot; what he gives instead is the
  heavy commits letting go of their tracking. **BUT HE DOES NOT TURN ON THE SPOT** — idle holds its facing and
  what moves it is the STEP-TURN, the hop and the GATHERS, so where he is looking is a fact you can read and be
  wrong about. **A GATHER TURNS HIS SHOULDERS, NOT HIS FEET**: `GATHER_SWEEP_MAX` caps the TOTAL a wind may bring
  round off the facing it STARTED from, and must stay under `180 − FALL_SECTOR` or the back pocket closes.
- **"DULL" IS A MEASUREMENT, NOT A FEELING** — 45 s of a hero walking a ring is 21 blows thrown, 93% committed, no
  lull past 0.73 s. Test-pinned, because the failure it guards is the fight going quiet.
- **LIGHT AND HEAVY ARE TELLABLE APART BEFORE THEY LAND** (`Weight`) — the gather's FIRE says which, and it must be
  WIDER THAN THE DOOR to be seen at all. A test forbids raising a move's damage without its tell following.
- **THE MOVES THE BOARDS CANNOT ANSWER GET THE LONGEST TELLS** — slam, charge and fall carry no parry window and
  their counter is DISTANCE, so `FALL_WIND_DUR` is bracketed from BELOW by every one of his own winds rather than
  by `foe.TELL_MIN`. **A RUN CLEARS THE DISC FROM THE MARK AND A WALK DELIBERATELY DOES NOT.** **A DISC IS DRAWN
  BEFORE IT IS BILLED** (`ringTell`), off the same mark and radius the mechanic uses, in EMBER because tan on tan
  is unreadable.
- **A FLANK BLOW HE SHRUGS OFF IS ANSWERED** (`counterFlank`) — it reads a blow that already landed and the
  bearing it came from (world state, never buttons), is clocked, is refused out of anything committed, and is
  **refused outright if the blow staggered him**: an earned punish window is never taken back.
- **THE JUMPBACK IS A LAST RESORT** — every door to the LEAP asks `harried`, a share of max HP banked at this
  spot. **ONE METER, TWO TIERS** (`foe.Sense.pressed`) is the pattern for any creature that must not flee at the
  first scratch. What he does instead is HOP, taken on PRESENCE.
- **STOOD DEAD BEHIND HIM HE FALLS ON YOU** — `fallwind` is the one move that steers AWAY from the hero, the spine
  coming round IS the tell, and **THE SAFE POCKET IS HIS QUARTER, NOT HIS BACK**: `FALL_SECTOR` is strictly
  outside `TOWER_ARC`, the gap test-pinned over 20° wide and paid for with the AIM. **AND THE BODY GOES BEFORE
  THE BODY GOES** — the wind takes 15° of the topple at the ROOT and the drop picks up from exactly there, one
  motion. **THE AFTERMATH IS THE REWARD.**
- **PHASE TWO FOULS THE GROUND** — once lit, anything that shows FIRE and STOPS leaves a `Gas` cloud, laid at the
  IMPACT FRAME so a stroke that MISSED still denies that ground. FALL and CHARGE are excluded (each is already
  position-denial); the lit CHARGE fouls the LINE instead, every `CHAOS_TRAIL_EVERY` of GROUND COVERED and never
  on a clock. **The cloud is the GROUP's, not the knight's** — it must keep burning after the body falls — and it
  carries NO poise and NO stance. **THE CLOUD'S EDGE IS THE MESSAGE**: over half the puffs born ON the rim, and
  `GAS_H` in METRES (1.3) never his scale, or it stands 4 m tall and reads as fog. **AND IT IS HIS EMBER, NOT
  CHAOS'S VIOLET** — the one call site that picks its own colour over `elemfx.sig`, because it is a tell first.
- **A CARRIED MASS IS CHASED, NOT ASSIGNED** — the general law his tower shield is the worked case of. The strap
  held the hub at the fist and the plank could not invert, and what was left was SPEED: `swipeOpenWant` and
  `shoveAcrossWant` are SCHEDULES with seams in them (a state changing, `shoving` clearing) and were read STRAIGHT
  into the arm, outside the spring bank, so the hub crossed **4.3 m in ONE FRAME**. Both are chased now, **and
  `guardUp` reads the CHASED value**, so mechanic and picture stay one channel and neither can step. **THE PICTURE
  LEADS THE FLAG AND MAY NEVER TRAIL IT.**
  - **AND THE FACE ITSELF IS CHASED** (`turnToward`, `DOOR_TURN_MAX`) — easing every channel was not enough, since
    the arm's own roll has singularities and a counter re-aims the whole basis in a frame: a soak caught **113° of
    face turn in ONE FRAME, standing in idle**, which a translation test cannot see because the hub barely moves
    while four metres of plank whips. **The tip is clamped AFTER the chase, not before** — a slerp between two
    legal near-horizontal faces on opposite bearings runs over the POLE. **AND THE CLAMP MAY NOT BAIL OUT**: his
    FORWARD is always a legal bearing.
  - **A SHIELD IS CARRIED, NOT WELDED TO THE FOREARM** — the arm AIMS it and nothing else: the face may tip
    `HANG_TIP` off his own horizontal and no further, and the plank length is whatever is left of his UP (his, not
    the world's, so a toppled body takes its door down with it). **Inversion is impossible by construction rather
    than by tuning a pose away from it**, and the SLAM is the one exemption — a FRACTION, not a flag. **AND THE
    STRAP IS A LENGTH, NOT A SUGGESTION**: a move's carry may swing the hub round the fist and may not take it
    further off than the grip.
  - **ANY ROTATION IS ABOUT ITS OWN CENTRE, NEVER ITS GRIP** (gripped high like a pavise, a pitch about the hub
    sweeps four fifths of a four-metre plank through the knight), and **THE ARM CANNOT CARRY IT — THE MOVE HAS
    TO** (the fist travels ~1 m and the door is 4). **A shield is driven with the elbow FOLDED and the body behind
    it**; a straight-arm punch turns the plank with the forearm and rams its edge.
  - **EVERY DIMENSION IS DERIVED AND COMPTIME-ASSERTED, NEVER PICKED** (`towerArc`) — widest chord against how far
    the face stands in front of the body axis plus a named allowance for the swept kit, chords asserted past the
    pauldrons, height past a wall's proportion. **THE RAM IS NOT THE WHOLE FACE.** **EVERY POSE THAT LERPS OFF
    `GUARD_*` MOVES WITH IT** — an absolute wind target silently loses its whole gather when the guard moves.
  - **THE MECHANIC AND THE PICTURE ARE ONE CHANNEL**, test-pinned together. **EVERY SWORD STROKE TAKES THE DOOR
    OFF HIS FRONT**, and **THE SWORD COMES HOME FIRST, THEN THE DOOR**; a test throws every stroke wind-to-recover
    and measures the blade's nearest approach to the face. **AND IT LEAVES HIS FRONT FOR THE WHOLE COMBO**, not
    per swing — a link's own gather holds it open.
  - **THE SWORD IS CARRIED HIGH — BLADE UP PAST HIS SWORD SHOULDER**, SOLVED by sweeping four channels against a
    target and taking the best that cleared the plank. On a body whose door covers his whole right side the rig
    cannot put a point past that edge without throwing the arm after it, so **the clearance is STRUCTURAL**: a
    blade overhead cannot be swung into a plank at his side.
  - **THE DOOR NEVER BREAKS; THE MAN BEHIND IT DOES** — no stamina pool on it, a small share of stance passing
    through so frontal pressure earns a stagger expensively, and **no poise ever**. **TWO PARRIES BREAK THE
    STANCE.** **OAK IS NOT A WARD** — `TOWER_NEGATE_ELEM` against anything thrown, so a rod is the way through his
    front. **NEITHER SHOULDER IS A FREE LAP**: the SHOVE hauls the door onto whichever flank you stand on and buys
    it with his FRONT — sword side on presence, shield side bought with DAMAGE, or the door collapses that whole
    flank onto one move.
  - **THE SOAK IS THE JUDGE, NOT THE PER-MOVE PROBES.** Debug entries drop him into one state from nothing; the
    seams live in a real fight. 120 s, 200 blows landed, 29 of 33 states visited, four invariants asked EVERY
    frame, failing with frame/state/geometry printed, **and asserting its own state coverage** so a soak that
    quietly stopped reaching the fall cannot pass having proved nothing.
- **Art:** `PLATE` = `.plain`, `BRIGHT` = `.steel` — `Mat.steel`'s specular is catastrophic on a face the size of
  a door, so `.steel` is for what is SMALL AND PROUD. The iron is BLUE-BLACK because everything outdoors here is
  warm. Ten `knight_*` voices sharing only `swing_light`/`swing_heavy` — **iron over bone, nothing alive inside
  it** — checkable on zero-crossing rate, every voice floored at 90 crossings/s.

**THE FUNGAL DUO** (`fungalduo.zig`) — a swordsman in your face and a magus who owns the rest of the floor.

- **THEY DIVIDE THE GROUND AND NEITHER COVERS THE OTHER'S.** The bands ABUT, and that is the whole of the pair:
  backing off the blade walks into the sprouts. **NEITHER KNOWS THE OTHER EXISTS** — no shared brain, no combo
  table; what makes them read as a pair is the geometry.
- **TWO GROUPS, ONE FILE** — a `FOE_GROUPS` row hands back ONE slice of ONE type, and a set of strokes and a set of
  spells are not one type. They share the file because they share rig, palette, pose and bands.
- **THE HEIGHT IS AUTHORED AS METRES OVER THE HERO AND THE WIDTHS RIDE IT** — written as their own constants the
  widths were `SCALE` copied by hand, and the first time the crown moved the body under it stayed the old width.
- **THE TWO STROKES DO NOT GET THE SAME BEARING GATE, BECAUSE THEY ARE NOT THE SAME SHAPE** — the slash SWEEPS so
  it gets the wind's turn plus its own arc; the LUNGE is a thrust down one line, so it gets the turn alone.
- **THE VENOM IS THE CLOCK ON THE FIGHT** — a guard answers the DAMAGE and not the buildup, so blocking every
  stroke still breaks the bar. **Both strokes carry it or the clock is on one.**
- **THE DISSOLVE IS LONG ON PURPOSE AND A STAGGER SPENDS IT** — caught halfway out he comes back solid and owes the
  whole cooldown, so pressure through the fade is the answer rather than a race. **A MAN IN HIS FACE GETS THE
  DUST**, which outranks both the retreat and the blink, so pressing him costs something.
- **A CLOUD STAYS WHERE IT WAS BLOWN**, and **it does not bill on the frame it appears** — that would be a blow
  with no tell. **NEITHER CAST HAS A BAND INSIDE THE RING IT WALKS OUT OF**: a lower minimum is a number nothing
  can ever reach.
- **THE BUNCH IS A MUSHROOM, NOT A BALL ON A STICK** — built at a cap radius of ONE so the world size is a single
  number; it comes up PAST its rest and settles back while the cap opens after it, and **the cap's COLOUR is its
  clock, because a warning you have to remember is not a warning.**

**THE CORRUPTED DRUIDESS** (`druidess.zig`) — bench her in `worlds/test_druidess.world`, never the shipped map.

- **THE VINES ARE THE COVEN'S, NOT HERS** — she reports `sowed`/`snared` for one frame and the group plants, ticks,
  bills and draws them. They are not bodies: no HP, no lock, no `tryHit`.
- **A CAST IS COMMITTED WHERE HE STOOD WHEN THE GATHER BEGAN**, and the buds drawn through the wind stand exactly
  where the vines will. A RUN carries him clear in the gather and a walk does not, both bracketed by comptime
  asserts against his own speeds.
- **THE SIDESTEP READS CLOSING SPEED, NEVER THE PRESS** — a rush is his position over the last frame; a man
  standing still in her face is not a rush and draws the drift instead.
- **THREE HEALING BREAKS**, each ONE call and ONE channel, counted the frame she commits so a stagger through the
  gather cannot buy a second wave off the same share. **ANY BLOW THAT LANDS ENDS THE CHANNEL, and that share is
  spent for good** — that is the whole of "go and stop her". **AND A CHANNEL NEVER CLIMBS BACK PAST THE SHARE SHE
  ALREADY BROKE AT** (`mendCeiling`), so the breaks come in order, each worth less, and the fight has a ceiling
  instead of three full heals.
- **SHE NEVER LEAVES THE ROOM, AND NEVER THE DRY GROUND** — the arena and a way to ask the world's water are
  stamped onto her each frame (`room`, `foe.Ground`, both off `@hasField`, so any creature that grows either gets
  it), and a drift that would cross wall or water turns along it. **OVER HIS HEAD FIRST**: the leap that gets away
  is the same arc the other way, landing past him.
- **A LEAP IS AN ARC WITH A HANG AND NO SLOPE AT THE GROUND** (`arcHop`/`arcAlong`) — up on a quarter sine, held,
  down on `1 - smoothstep`, ground covered on a half-cosine so the speed is nothing at touchdown.
- **SHE IS THE TELL, NOT THE SPEAR.** Nothing is drawn on the ground through the wind — the coil is the whole of
  it. **Every tell of hers is a POSE first**; a mark on the ground is only ever where a thing will stand.
- **THE TANGLE IS THREE SPRINGS ON HER HEADING**, so a turn settles in three beats, and **THE VINES ARE ALIVE, NOT
  POSTS** — all of it draw-side off the vine's own clock; the bills do not move.

### Creature laws that came out of one body and now bind all of them

- **SUBMERGED CANNOT BE STRUCK, AND THAT IS GEOMETRY** — depth rides as a NEGATIVE lift through `foe.bodyPoint`,
  so hurt sphere, bar and reticle all sink and the swept test refuses it on its own. **NO LOCK-ON WHILE UNDER OR
  DISGUISED** — `hidden()`, found by `@hasDecl` in `game.disguised`, the same predicate `Model.draw` hides the
  body behind, and never a clock of its own.
- **A SPOT IS COMMITTED THE FRAME THE TELL COMMITS IT** — the mound stopping, the gather starting.
- **THE CORPSE IS THE MECHANIC** (necro) — a body inside `RAISE_R` of a living necromancer **STOPS DISSIPATING**
  (`heldOpen`, read by `foe.dissipate` through an `@hasField` opt-in), so the held corpse is the FIRST tell and
  arrives before the cast. **IT IS A PLACE, NOT A LIST**: flags cleared and re-earned each frame off where bodies
  lie, walked in order so two cannot claim one body. **A BODY MAY BE RAISED ONCE**, into a light stun so it cannot
  swing out of the ground. **THE CREATURE ONLY REPORTS IT** — `game.applyRaises` does the raising and
  `foe.rekindle` reads FIELDS ONLY; the STATE it comes up in is each creature's own.
- **A RING COMMITTED TO THE GROUND OUTLIVES ITS CASTER**, is not parryable, and carries the RING as `hitFrom` so
  stood on the mark there is no bearing to catch. **IT TAKES THE TARGET'S OWN `pos.y`**, never the caster's, or a
  ring twelve metres away is depth-culled under the turf. **A RING IS A BURST, NOT A COLUMN** — its radius grows
  with the caster, its height does not, because what it has to reach is the hero.
- **A FUSE BURNS ROUND THE RING RATHER THAN FILLING IT** — the last rune lighting IS the blow. Built from
  `drawSphereEx` and nothing else: `drawLine3D` is one pixel however close, and a `drawTriangleStrip3D` annulus
  came back invisible.
- **THE SPELL IS BILLED AFTER THE BLADE IS** — hold the edge as `pendRaise`/`pendLay` until `tryHit` resolves, so
  a stroke on the release frame cancels it and cancels NOTHING else.
- **A HOP IS INTEGRATED, NOT SAMPLED** — `LEAP_SPEED * sin(pi*u)` integrated across the clamped slice of each
  frame, so 30, 60 and 144 Hz travel the same distance. A stagger in flight keeps height and vertical velocity.
- **A FLIGHT TUCK IS FOLDED ONTO THE GROUND SOLVE, NOT SWAPPED FOR IT** (`foldInto`) — an extra rotation at hip and
  knee carrying its children, so the legs cannot pop the frame the soles leave the floor and a rotation cannot
  change a bone's length.
- **THE BLADE FINDS A THIN BODY THROUGH POSED HULLS** (`foe.hullTouches`), with `centerWorld`/`hurtRadius` only the
  enclosing broad phase — a chest-centred sphere misses the skull and the shins. **A FIXED STATURE FRACTION IS NOT
  A CROWN**: `topWorld` reads the POSED hulls, and borrowing another creature's `TOP_F` reported 3.28 m for a
  2.78 m body.
- **TALL AND SKINNY IS TWO DIALS AND THE RATIO IS THE CLAIM** — stature and `hx`/`sx` both; either alone is
  satisfiable by the wrong creature, so a test measures stature over shoulder SPAN against the body beside it.
- **`pos.y` IS THE GROUND UNDER A FLYER AND `hover` IS WHAT IT FLIES ABOVE THAT** — every world point measured off
  `pos.y + hover`. **ALWAYS `airborne()`**: the terrain gate never applies and nothing shoulders it, **but it is
  NOT exempt from `env.resolveActor`.**
- **A FEED IS A BLOW AND THEN A HOLD, DOWN DIFFERENT CHANNELS** — the bite is a real `foe.Blow`, the swallow a DRIP
  billed per SECOND. A shield answers the first and only the ROLL the second, and `holds()` is re-asked every
  frame and tests height as well as bearing.
- **A THING IN FLIGHT LANDS ON EARTH, NOT ON WHATEVER HE IS STANDING ON** (`foe.landed`) — nothing in `foes/` can
  reach `env.groundAt`, so a shot carries the floor it was thrown from and is spent on the LOWER of that and his.
- **A HANG BEFORE A HOMING SHOT IS THE MOVE**, its home speed asserted at comptime under `hero.SPRINT_SPEED`. **THE
  STEER IS CAPPED, NOT LERPED** (`mathx.turnToward`) — `normV(from + k·(want − from))` stalls as the angle grows
  and at dead opposite is a fixed point, so the one bearing the hang exists for was the one that did not work.
  **AND A BOB'S RATE HAS TO BE IN THE STEP OR IT IS NOT ONE**: added as `A·cos(wt)·dt` it is the integral of the
  wave, and 0.16 m authored arrives as 0.02 m of wobble.
- **OPEN, IT TAKES MORE DAMAGE** (`frailty`) — on the BLADE in `tryHit` so cull, threat and shield all see the blow
  that landed. **DAMAGE ONLY**: `poise` and `stance` ride through untouched, because `POISE_MAX` is solved to sit
  between his light and his heavy and a multiplier there quietly puts a light poke through it.
- **CORNERED IS TWO DISTANCES AND A CLOCK** — inside the ring the ranged move is useless in, AND the gap did not
  open this frame, held for its own hold and draining at its own decay. **Never a read of what he is holding.**
- **A CHARGE COMMITS TO THE LINE IT LOADED ON** and does not steer inside the drop.
- **A CORPSE WILTS FROM WHATEVER THE BLOW CAUGHT IT WEARING** — snapping shut is a pop and ramping from wide is the
  same pop the other way. **A ROOST HANGS IN THE BAND IT BITES FROM** — a roost nobody can reach cannot be the
  thing that wakes the rest of them.
- **PARTICLE COLOURS ARE LITERAL SCREEN VALUES WHERE MESH COLOURS ARE ALBEDOS**, and a substance drawn both ways
  needs two palettes. **A ROOT PITCH ROTATES ABOUT THE POINT ON THE GROUND**, so the root is lifted by exactly
  what the tip sinks. **AN EFFECT'S PHASE IS ITS OWN DECAY, NOT A CLOCK BESIDE IT** — a landing ring runs off
  `thud`, not `self.t`, which resets on every state change.
- **`stageGather` AND NOT `stageRise`** — `shots.runMapShots` finds a creature's signature move off `@hasDecl` of
  that ONE name, and under any other the creature goes unshot.
- **A RETRIGGER, NOT A LOOP** (`WHINE_EVERY`, `HUM_EVERY`) — raylib cannot loop a synthesized take, so cut a hair
  LONGER than its own period; gapped, it chatters and reads as a helicopter.

## Combat

**The two sides are tuned SEPARATELY.** A stagger you inflict is a punish window you must be able to walk into; a
stagger you suffer is time taken off the player. Hence `FOE_*_STUN_DUR` well past the hero's, `FOE_REGEN_*` far
slower.

- **NOBODY IS POISE-DAMAGED WHILE ALREADY REELING, EITHER SIDE** — while a stun runs incoming poise is dropped and
  when it ends poise goes back to FULL, both tiers; STANCE is dropped with it and only HP still lands. `Vitals` owns the
  clock and it ticks BEFORE the regen gate, or a foe's `regenDelay` outlasts the window and the immunity never
  lifts. A GUARD BREAK is the one door `hit()` misses — `hero.enterStun` arms it.
- **A DRIP IS NOT A BLOW** — anything that HOLDS bills damage every frame (`Vitals.drip`), and a blow's side
  effects cannot be billed at that rate. TWO clocks: `sinceHit` gates the poise/stance refill and only a blow
  moves it, `sinceHurt` is what the floating bar reads and anything taking HP moves it. **A drip that KILLS is
  reported, not acted on** — only the creature knows how to die.
- **A BLOW MAY TAKE THE BLUE BAR** (`Hit.fp`, the shade's touch, the only thing that does) — NOT part of
  `Hit.raw()`, because what a shield's stamina bill measures is the WEIGHT of the thing that hit you.
- **A TIMED STATUS REFRESHES, IT DOES NOT STACK** (`Root.grab`, `Regen.start`).
- **A THROWN SORCERY REACHES ONE BODY; A HELD ONE REACHES WHAT IS IN FRONT OF HIM** — thrown into a warband it
  picks ONE victim, so its reach is a search and never a blast, and the FX is sized to the BODY, not the reach.
  **THE RIME BREATH IS THE ONE EXCEPTION, WHICH IS WHY IT IS A CONE** — a direction held in front of himself,
  answered by not standing there.
- **AN EFFECT'S CLOCK IS DERIVED FROM THE MECHANIC'S, NEVER PARALLEL TO IT**, and when the effect STAGGERS its
  parts, its container outlives the mechanic by that stagger.
- **FEEDBACK ON A CREATURE IS SIZED BETWEEN TWO FAILURES** — under, scenery round the ankles; over, it hides the
  creature it points at. Judge against the CREATURE, never the hero who caused it.
- **A FLOATING BAR TIMES OUT; THE FIXED ONE DOES NOT**, and it goes with the RETICLE, not `g.lock`, so a suspended
  lock takes the bar down with the dot. **AND IT MAY NOT CLIMB OUT OF THE FRAME** (`hud.FOE_CEIL`) — overhead
  unless that would put it above three quarters of the screen. ONE rule for every creature. **A HEAD CAN GO
  BEHIND THE EYE**: stood at a giant's feet its crown is above AND behind the camera, which `projectToScreen`
  refuses, so the fallback anchor is the CHEST.
- **THE RETICLE RIDES THE BODY, NOT A HEIGHT OFF THE FEET** — each creature names the PART its mark rides and a
  point in that bone's frame; a bone matrix already carries scale, facing and `pos`, and every `spawn` poses
  before it returns. A test measures the mark's swing OFF THE CREATURE'S OWN AXIS, not its height, because a
  fixed mark still rises and falls on a hop.
- **ONE RAIL PER BOSS, AND THE RAIL IS THE ROW'S INDEX** (`game.BOSS_RAILS`) — two bosses sharing rail 0 wiped
  each other's frac, fade and chip tail every frame. Chip state is PER RAIL, and `game.aggroRing` takes each
  rail's ring off `FOE_GROUPS` so a bar cannot wake at a different range from the creature it shows. `game.zig`
  owns when a bar shows and SUPPRESSES that body's floating bar — **one number may not be read in two places.**
- **A BOSS BAR MAY NOT BE GATED ON A RANGE THE CREATURE'S OWN DESIGN EXCEEDS** (`game.sealedInWith`) — being
  SEALED IN with something is the fight whatever the range, and `Leash.roused` is a timer topped up only by being
  HIT, so chasing one boss let the other's bar lapse mid-fight.
- **EVERY BAR THE RUN LEFT ON SCREEN GOES WHILE THE SCREEN IS BLACK** (`game.dropRunHud`, `hud.dropBossBars`) —
  `bossK`/`spiritK` only tick inside `hud`, which the chrome fade and `rest.active()` both stop calling, so they
  FREEZE at full and the rail comes back carrying the dead run's HP and chip tail.

**Stamina.** **AN EMPTY BAR LOCKS OUT roll / attack / sprint** — not time theft: the consequence of a choice made
a second earlier, readable off a bar. **WALKING IS NEVER GATED** (running dry caps `mv.speed`, denied at the
SOURCE so `sprintingMove` stays the one definition of a sprint). **RUN IT OUT AND YOU ARE WINDED** — sprint
denied until the bar is back to HALF, a LATCH and not a `cur == 0` test, latched from every path that moves
`cur`. **YOU MAY ACT ON ANY STAMINA ABOVE ZERO** — `canAct()` is `cur > 0`, NOT `cur >= cost`, and that asymmetry
is the PANIC ROLL. **A COMMITTED ACTION IS NEVER CUT SHORT** — `spend` floors at 0, nothing refunded or aborted.
The refill pauses while attacking, rolling or sprinting, then waits `STAM_DELAY`. **A REFUSED ACTION IS SHOWN**
(red ring): under zero-input-lag, silence is indistinguishable from a dropped input.

**Guarding — the plain DS1 block, not ER's.**

- **IT IS A HELD STATE, NOT A COMMITTED ACTION** — `setGuard(want)` every frame with the button's level,
  re-derived from scratch. Call it AFTER `sprinting`.
- **THE SHIELD IS A DIRECTION** (`GUARD_ARC`, 65° either side), not a bubble, which is why guarding cannot answer
  a warband the way rolling can. A blow with a zero `fromDir` is never blocked, which is what lets `--shot` force
  reactions with synthetic hits. **SO A BLOW CARRIES WHERE IT CAME FROM** — every group's update returns
  `?foe.Blow` (hit + attacker pos), not a bare `?combat.Hit`; an arrow's direction is its own velocity reversed.
- **IT COSTS STAMINA, NOT POISE.** **CHIP GETS THROUGH AND CHIP CAN KILL**, routed through `Vitals.hit`; stability
  is poor by design, and **A BOARD MAY NEVER STOP A BLOW OUTRIGHT** (`GUARD_NEGATE_CAP`).
- **EMPTY THE BAR UNDER A BLOW AND THE GUARD BREAKS** — heavy stagger, and the shield cannot come back up until
  the pool refills. The danger is the NEXT hit.
- **`takeHit` RETURNS WHAT BECAME OF THE BLOW** (`HitOutcome`) and `game.heroTakes` is the ONE place that turns it
  into a felt beat.
- **THE STANCE LAGS, THE BLOCK NEVER DOES** — `guarding` is live on the button, `guardB` a ~0.1 s visual blend.
  **Nothing mechanical may read `guardB`.** **THE MAN MOVES, THE SHIELD HOLDS**: recoil goes into the BODY.
- **The shield is not a bone** — it rides the left wrist through `hero.shieldFit`, DERIVED from the stance angles
  (their inverse), or the first retune swings it off its own arm.

**Parrying — L2, the shield's own skill.** L2 is the left-hand armament's SKILL slot, routed by that hand exactly
as L1 is, and it asks NOTHING about whether the guard is up. On the mouse the two halves of L2 part company
(`PARRY_KEY`), because RMB is the guard's held level.

- **THE WINDOW AND THE ANIMATION ARE TWO CLOCKS** — the catch is open ~0.16 s, the shove plays a quarter second
  after it shuts, and `canGuard` refuses the whole time. **That tail IS the price.** **IT IS SLOW OFF THE MARK**
  (`PARRY_OPEN` 0.10 of 0.52): widening `foe.PARRY_LEAD` makes catches easier, this makes STARTING one a
  commitment. Separate dials on purpose.
- **THE ATTACK DIES AT CONTACT; THE HEAVY STUN IS EARNED.** `PARRY_HIT` is STANCE and nothing else — no damage, no
  poise — so a catch can never resolve as a flinch: it breaks the stance or it does not.
- **A WINDOW IS `foe.PARRY_LEAD` SECONDS BACK FROM THE IMPACT FRAME** — one number, in seconds, for EVERY creature
  and move, and it IS the difficulty. **It is 0.18**, every creature's tests BRACKET it from above (a window may
  never be more than a fraction of the tell in front of it), and it is **DELIBERATELY NOT A PERK.**
- **TIMING EARNS THE CATCH; CONTACT DELIVERS IT** (`Parry.contact`) — `pending` preserves a valid early timing
  while the attack continues unchanged, `setParry` preserves it across shield stamps, and losing shield, facing,
  reach or attack cancels it. Swept weapons resolve after posing and before damage; others use `toImpact`.
  `Parry.window` includes the impact-crossing frame so 30 Hz cannot skip a catch.
- **THE CREATURE READS THE SHIELD, IT NEVER REACHES FOR IT** — each MOVE answers for its own frames and reach at
  its own `parryable`. Adding one is a `parry` field, a `toImpact`, a `parryable` and the group's
  `setParry`/`anyParried`. `parryBeat` fires ONCE a frame for the whole field.
- **WHAT IS *NOT* PARRYABLE IS A DECISION, WRITTEN AT EACH `toImpact`** (or at the impact site of a move with
  none): a projectile is not a blow, a GROUND DISC has no bearing to catch, a POURED ELEMENT has no swung mass.
  Broodlings and the LEECHFLY are out by design — its counters are the ROLL and the ranged kit, and a window on
  the stab would make the boards the answer to a flyer. **HYPER ARMOUR IS NO DEFENCE**: it refuses poise off the
  blade, and a parry deals neither damage nor poise, so the uninterruptible slam is exactly the move the boards
  can still stop.
- **IT IS A SWIPE, AND THE SWIPE COMES FROM THE WAIST** — a shoulder yaw turns the boards' FACE with it because
  `shieldFit` is that yaw's inverse; the TRUNK turns arm and boards together. **THE SHOVE MAY NOT BREAK THE
  FOLD**: the shoulder takes `PARRY_PUNCH` and the elbow gives back exactly as much, so what travels is the HAND.
- **A CATCH KICKS A SPRING** (`foe.Deflect`) — a sideways weapon deflection with overshoot, legs planted,
  two-hand grips solved afterwards. Contact gets the large flash, sparks, clang and rumble. **THE SWIPE ITSELF
  THROWS A GLINT, CAUGHT OR NOT**, once on the whip's peak frame and **LAID ALONG THE ARC, NOT THROWN FROM A
  POINT** so it is a STREAK from the first frame; always less than a catch, never a different colour.
- **JUDGE IT FROM ABOVE** — a lateral arc foreshortens to nothing head-on. `--shot --shot-only parry_study`
  asserts the real attack reaches, the parry catches, and the caught blow deals no damage, at 30/60/144 Hz.

**The jump — A/Cross** (keyboard `V`; A is strafe-left, so the letter cannot be mirrored). Traversal, not a
technique. NO stamina, no jump attack.

- **TWO NUMBERS ARE THE DECISION AND THE OTHER TWO ARE SOLVED** — `JUMP_APEX` (1.4 m) and `JUMP_AIR` (0.852 s);
  `JUMP_G` and `JUMP_V0` fall out. The apex clears FIVE terrain risers where a walk gets two, pinned against
  `wf.HEIGHT_STEP` both ways — **AND HIS REACH (`JUMP_APEX + STEP_UP`) STAYS UNDER THE LEAST DROP THAT CUTS**
  (`wf.cliffMinDrop`, 2.1 m), so a painted face is a wall to the jump as it is to the walk.
- **THE INTEGRATOR IS THE CLOSED FORM**, not `v -= g·dt; y += v·dt` — that pair loses `g·t·dt/2`: nine centimetres
  of apex at 30 fps and none at 240. A test flies all four rates.
- **`pos.y` IS STILL THE GROUND UNDER HIM** — `game.groundActor` its only writer, `hero.lift` what he flies above
  it by. The height integrated is `airY` and `lift` is DERIVED off it every frame, which is what makes running
  off a ledge work. **`lift` is ZERO unless he is airborne**, so a teleport can never strand him on nothing.
- **GRAVITY LIVES IN `tickClocks`** — a blow mid-air routes to `updateStun` and a death to `updateDeath`, and a
  man who stopped falling because he got hit would hang in the sky. `dropActions` deliberately does NOT clear
  `jumping`.
- **IT IS `committed()`, beside the roll** — no double jump, no roll or cast out of the air, a sprint that stops
  when his feet do, and an attack pressed mid-flight BUFFERED into the one slot and fired on landing. **THE STICK
  BENDS THE ARC AND MAY NEVER RE-PRICE IT** (`AIR_TURN_RATE`): heading and ground speed commit at takeoff.
- **HE MAY FLY OVER ANYTHING HE IS ABOVE, AND NOTHING ELSE** (`env.flyStep`) — his own FEET replace the riser
  rule, plus the walk's `STEP_UP` allowance since on the takeoff frame his feet are still on the ground he left.
  **THE SAME RULE RUNS ON ALL THREE THINGS THAT CAN BE IN THE WAY, each off its own top**: BODIES in
  `collideActors` (off `topWorld`) and the world's SOLIDS in `env.resolveActor` (skip any collider whose
  `Solid.h` is under his `footY`) — **no `STEP_UP` allowance there.** **REFUSED, `flyStep` SLIDES** along the
  wall off the same gradient the walk uses. **FOES are deliberately still measured at `pos.y`.**
- **THE FALL** (`hero.fallDamage`) — free under `FALL_FREE` 4 m, certain death at `FALL_DEATH` 13 m, a power curve
  between, all as fractions of `hpMax`. **MEASURED OFF THE HIGHEST POINT OF THE FLIGHT** (`airTop`), or a jump
  taken one stride before the lip is a shorter fall than a walk off it. **THE GROUND IS NOT A BLOW** — billed
  straight to `vit`, past armour and past the guard. **DEXTERITY BUYS A QUARTER AND NOT ONE METRE**: it never
  touches the height that kills, and `FALL_MIN_FRAC` stops it making a drop free.
- **THE LENS TAKES ONLY A SHARE OF IT** (`camera.LIFT_SHARE`) — decided once, in `camera.zig`.
- **THE POSE IS THREE TERMS OFF ONE NUMBER, the vertical velocity** — DRIVE up, TUCK where velocity passes through
  ZERO (which IS the apex, so the pose cannot drift out of step with the arc), REACH down. **The arms must survive
  the apex.** NO ROOT PITCH; the whole fold is spine and chest, test-pinned under 20° off upright.
- **THE ABSORB IS VISUAL ONLY, AND THAT IS A LAW** — a landing recovery that took the stick off him would be
  hitstop on the most ordinary move in the game. **THE BEAT GOES ON THE LANDING, NEVER THE TAKEOFF**, and the
  gait phase keeps running so he lands back into the stride he left with. No footfalls in mid-air.

**In combat, and the quick bar.** **ONE FLAG SAYS A FIGHT IS ON** (`game.inCombat`), and nothing about the HERO is
in it: a creature counts if its `Leash` is ROUSED or if he is inside the range it notices him at — **and that
range is the group's own `FoeGroup.aggro`.** Sight is deliberately not asked (`env.sees` flickers round a
corner). A CORPSE DOES NOT COUNT. **IN COMBAT A CONSUMABLE COMES OFF THE QUICK BAR OR IT DOES NOT COME AT ALL.**

- **THE BAR IS THE CROSS'S DOWN SLOT** (`combat.Quick`, ten entries), the two flasks its first two so a fresh game
  plays as it did; `Flasks` still owns their CHARGES and `combat.quickCount` is that split, ONE copy. **CYCLE
  STAMPS `flasks.sel`, it does not cycle it** — `Quick.cycle` is the only cycle. **A REMOVAL LEAVES ITS HOLE**: a
  list that compacts under you mid-fight is one you cannot learn.
- **EACH BAR ENTRY IS ITS OWN SOCKET ON THE PAGE** — Confirm puts a kind in THAT socket (`Quick.put` MOVES rather
  than copies). Rows are FILTERED to what he carries, so a kind's ordinal is not its row and `pickIndexOf` counts
  it out the way `candidates` builds it.
- **THE ONLY FLASK THE MAP CAN PLACE IS AN EMPTY ONE** — found, it is not an item: `Flasks.found` is ONE MORE IN
  THE POOL on the crimson side, EMPTY until the next fire. `FLASK_CAP` 14, ER's. The pool rides the save's
  `ready:` row as a fourth number, so an older file keeps the default three. No golden seeds — `golden_seed` is a
  `RETIRED_TAGS` row, skipped by the bag loader instead of refusing the file.

**Status effects — the shape every one takes.** **ONE METER DOES ALL THREE JOBS** (`combat.Status`): hits fill it;
full, it PROCS; the same meter becomes the CLOCK, draining over the effect's life while it bills HP. **It cannot
be topped up while it drains** — where a BURST status (bleed) resets to nothing and re-procs at once.

- **DECAY IS WHAT MAKES IT PRESSURE** — the meter falls once you STOP taking doses, so spaced hits never proc and
  LINGERING is the whole cost. **A SOURCE HANDS OVER BUILDUP, NEVER HP**, and keeps no clock of its own.
- **THE PROC IS BILLED AS A DRIP** (no poise), taking the row's `hpFrac` of MAX HP over its span — a fraction, so
  it is worth the same on a Vitality build as on a fresh sheet. **BUILDUP AND RESISTANCE ARE TWO DIALS AND BOTH
  ARE LIVE**: gear and the tree slow the METER filling while the element's resistance cuts each TICK.
- **BUT CHAOS DOES NOT POISON BY ITSELF** — a blow's chaos builds the meter only with `Hit.venom` set. What
  poisons: the duo's strokes, orb and bunch, the deer's spores, the rotgorger's bite. What is only damage: the
  bolt, the siphon, the bolt's gas, the knight's lit stroke and his gas, the druidess's whip.
- **THE DRAIN IS SILENT AND UNFLASHED** — the red edge and the beat belong to a BLOW, and **the PROC gets the whole
  of the feedback, once**: one shake, one voice, one flash.
- **THE BAR HAS TWO FACES OFF ONE NUMBER** — violet FILLING, toxic YELLOW once gone off, **nothing at all** while
  empty. Not green: it sits directly under the stamina bar. The foe's own 2 px row is the same — a tint on a 54 px
  red bar is a hue nobody can name.
- **THE METER SITS ON THE BODY, NOT ON HIM** (`Vitals.ails`) — filled by `Hit.dose` through the one `Vitals.hit`
  and ticked for a creature in `foe.grip`, which every creature already called, so no foe grew a field.
  `Vitals.ailRate` is the dose multiplier and the ONE place it is applied.
- **AN ENVENOMED EDGE IS WHAT PUTS ONE IN A FOE** — the dose is CARRIED through `Hit.scaled` rather than
  multiplied, like `launch`: it belongs to the coating, so a heavy swing does not poison harder. A blow that
  KILLED doses nothing.
- **A BONFIRE CURES IT** (`makeWhole`), and a death is a return to one. Two sources at once dose as **both** — two
  `add` calls, not a max.
- **TEN METERS, EACH SAYING WHO CAN CARRY IT** (`combat.Ail`) — poison, burning, chill, stun, bleed, sleep,
  confusion, charm, berserk, stupefy. A full meter reaches the state machine: stun and sleep come out of
  `foe.grip` as `downed`, chill and stupefy take the FEET, charm and confusion re-point `foe.Threat`.

**Resistances — PoE2's four.**

- **PHYSICAL IS NOT ONE OF THE FOUR.** `Elem` is fire/cold/lightning/chaos; what mitigates physical is ARMOUR, its
  own curve (`armourTaken`, `A/(A + 5*dmg)`). **Do not add a "physical resistance".**
- **75 IS THE CAP, NEGATIVE AMPLIFIES** — stored uncapped, capped on READ (`Resists.at` vs `.raw`).
- **A SPREAD IS WRITTEN BY NAME** — `combat.resists(.{ .fire = -45 })`, matched at comptime so a rename is a
  compile error; an array literal in enum order silently shifts on a fifth element.
- **POISE AND STANCE BELONG TO THE BLOW, NOT THE BODY** — `guardChip` is damage only for the same reason, and a
  shield is billed on the RAW blow.
- **COLD IS THE ONLY ONE THAT DOES SOMETHING BESIDES DAMAGE** (`combat.Chill`) — a hold on the FEET, travel
  multiplied by `CHILL_TRAVEL`, taken as a post-step gate. A chilled creature is not a slowed creature, it is one
  that cannot close. **Deliberately NOT time dilation.** **NOT SKIPPED FOR A FLYER** — the one place it parts
  company with the terrain gate beside it. Built to be worn by EITHER SIDE.
  - **BUT A BLINK IS NOT TRAVEL** — the gate scales a frame's whole DELTA and a body that WARPS sets that delta
    rather than stepping it, so each answers `warped()` for the one frame, duck-typed the way `airborne()` is.
  - **WHAT IT STILL DOES NOT TAKE IS THE GAIT** — `movedDist` is filled BEFORE the gate, so a chilled walker's
    legs cycle 1/`CHILL_TRAVEL` faster than the ground it covers. Either the gate owns the phase or the movers
    scale the GAIT (never the step) — the owner's call, not a sweep's.
- Every foe carries its own table, authored where its HP is (`initFoe(..).withRes(..)`):

  | creature | fire | cold | lightning | chaos | why |
  | --- | --- | --- | --- | --- | --- |
  | gaping toad | +40 | −30 | −25 | 0 | wet out of a bog, cold-blooded |
  | skeletal archer / warrior / Bone Knight | −35 | +60 | 0 | +45 | dry bone burns; no flesh to freeze or poison |
  | one-eyed ogre | +30 | +30 | −15 | +20 | too much mass, but stands in an open field |
  | kobold (all three) | −45 | +20 | 0 | 0 | fur goes up — the fire arrow IS the answer to a warband |
  | brood mother / broodling | −25 | +35 | 0 | +75 | chitin and its own acid |
  | egg sac | −70 | 0 | 0 | +75 | dry silk over a membrane |
  | shade | +30 | +65 | 0 | −45 | nothing to burn, and cold is what it already is |
  | leechfly | −55 | −25 | 0 | +35 | a wing is a membrane; the chaos is what it has been drinking |
  | the Rooted | −70 | +40 | −20 | +30 | dead dry wood; lightning splits it |
  | sporeling | −50 | +15 | 0 | +75 | a damp fungus stuffed with its own element |
  | Delver | +20 | −30 | −40 | 0 | packed earth over a damp hide; a bolt EARTHS |
  | Necromancer | −35 | **+75** | 0 | +45 | cold at the cap — it is the one thing that deals cold |

- **THREE AND A HALF OF THE FOUR ARE LIVE** — FIRE, LIGHTNING (the thundercrock's alone; nothing deals it AT the
  hero), COLD which **BOTH SIDES** deal (the necromancer's ring at him, the rod's rime breath back, both neat with
  no physical), and CHAOS, the one he meets most. **WHAT HE OWNS ANSWERS THREE OF THE FOUR** — **LIGHTNING IS
  STILL 0 ON PURPOSE**, because a piece that turned what nothing deals would be honestly inert.
- **A WARD AND A COATING NAME THEIR OWN ELEMENT** (`Use.ward`, `Use.grease`) — ONE column each and one at a time:
  a second tonic MOVES the ward rather than opening a second column. `item` is a leaf, so `combat.elemOf` is the
  crossing and a comptime walk pins the two enums field for field. `makeWhole` carries resistances across a fire.

**The character sheet** (`stats.zig`) — seven attributes; `hpFor`/`fpFor`/`staminaFor` turn Vitality/Mind/Endurance
into the bars at ER's soft caps. **The starting sheet reproduces the tuned bars exactly**: every attribute starts
at 15, where the curves yield 70 HP / 60 FP / 105 stamina, so `hero.HP_MAX`, `combat.FP_MAX` and `combat.STAM_MAX`
are DERIVED and a test pins all three. **The bars take their size from the sheet in one place** — `makeWhole`.

## The passive tree (`passivetree.zig`) — PoE2's, radially

Three arms out of one hub, never NAMED on screen (colour and direction carry which is which). Nothing is a class:
all three open from the first souls you spend. `Arm.stat` is the class node, the arm said in one attribute; six
`Branch`es, two per arm in arm order (`Branch.arm` is arithmetic, pinned at comptime), each a climb of
`PER_BRANCH` ending in its own keystone. 75 nodes in the arms plus six bridges: 81. Keystones: `Sanguine Pact`
(leech), `Berserk` (the bargain), `Misty Step`, `Hail` (thrown), `Wellspring`, and **`Chaos Bloom`, the one
keystone that is a MECHANIC.**

- **A GRANT IS A NUMBER ON `Bonus` OR IT DOES NOT EXIST**, and **THE IDENTITY IS THE FIELD'S OWN** — 0 for
  anything added, 1 for anything multiplied, false for a flag. A test pins every identity, pins that the tree
  moves every one, and pins that **no `Grant` variant is unreachable**. **ONE GRANT PER NODE.**
- **A BARGAIN IS STILL ONE GRANT** (`Grant.sacrifice`) — costs ADD and gains MULTIPLY, and `hero.hpMaxOf` clamps
  the pair with the charms at 0.9 of the bar.
- **THE CULL IS READ BEFORE THE BLOW, NEVER AFTER IT** (`Blade.cullAt`, applied in `foe.strike`) — asked of the HP
  the body walked into the swing with. Carried on the BLADE, stamped only on `game.heroBlade`.
- **THE CHAOS BLOOM IS `knight.Gas` READ FROM THE OTHER SIDE** — same type, same life, dosed through `pierceFoes`
  as a zero-length `through` blade at the cloud's radius, laid at the IMPACT frame.
- **YOU CLIMB, AND THE LINK IS THE RULE** (`feeders`/`Tree.reached`) — a node opens the moment ANY ONE of the
  things it hangs off is yours, and `feeders` is asked by the DRAW and by `locked` alike so the page cannot gate a
  branch on something it does not show. **IT RETURNS A SLICE, NOT A PAIR OF OPTIONALS**: as `[2]?usize` a
  one-feeder node carried a trailing null, every reader read that as "hangs off the hub", and the whole tree
  opened at once. **An EMPTY slice is the hub.** The capstone is the one node with two ways in.
- **TAKING A NODE IS THE LEVEL** — one press spends the souls and puts the node on the board; no point pool.
  `Tree.take` hands back what it charged, so `game.bonfirePick` is the one line that can bill him and **the ONLY
  thing in the game that spends souls.** **THE TREE OWNS THE LEVEL, NOT THE SHEET**: level is COUNTED off the
  board (`spent() + 1`) and every attribute past the starting sheet came off a node. The STATS page is read-only
  for good.
- **SOULS, NEVER RUNES**, in the code as well as on the page. **THE PRICE IS MEASURED AGAINST A BODY** — toad 60,
  archer 130, mother 240, so `costAt` is set where the first node is three archers and the whole 21 is ~80k. ONE
  price per level whichever node it lands on.
- **THE REST OF THE GAME READS FIELDS OFF ONE `Bonus`**, stamped by `game.applyTree` → `hero.applyPerks` (sheet +
  resistances + perks in ONE call). **Nothing outside `passivetree.zig` walks the node list.** Five hero-local
  readers: the roll's stamina, the roll's i-frames, the cast's cost, the cast's blow (`Hit.scaled`, the WHOLE
  blow) and the guard's negation.
- **SPENT AT A BONFIRE, READ ANYWHERE** — the book's last page is the wheel READ-ONLY, `drawPage` is ONE copy
  drawn by both, `spendable` the only difference.
- **THE WALK IS GEOMETRIC** (`book.slotStep`'s law) — an ordinal walk steps between nodes nowhere near each other.
  A test floods all four directions from every node.
- **A RADIAL LAYOUT TAKES THE THUMB'S OWN BEARING, NEVER ONE OF FOUR** — arms run out at 0/120/240°, so snapped to
  four axes and gated by the 32° dead cone the thumb pointed AT a node landed IN the cone on two arms of three.
  `step` takes a HEADING and its own wedge chooses; CROSS and KEYS still hand it a cardinal, a LIST still takes
  the sign of an axis. **A WHEEL IS STEERED, NOT RE-PRESSED**: a turn past `AIM_TURN` fires at once and a drift
  under it carries the repeat onto the bearing the thumb is on NOW.
- **THE FRAMING IS A SQUARE ON THE HUB, NOT A FIT OF THE BOUNDING BOX** — three arms at 120° have a bounding box
  whose centre is nowhere near the hub. `unit` comes off the panel's SHORT axis so it fits either way up, and
  `VIEW_R` is the outer radius of what is actually DRAWN. Test-pinned at three aspect ratios. **THE ARMS ARE
  NEVER CAPTIONED, so nothing reserves room for one.**
- **THE MIDDLE IS A PLACE THE CURSOR MAY REST** (`HUB`, indexed one past the last node so every `NODES[i]` site is
  untouched) — it takes no press and is never a purchase.
- **THE THREE STATES SEPARATE ON FILL, NOT ON HUE** — taken solid, open a lit rim over the seat, locked the rim
  gone to nothing; the arm's colour already carries the arm. **ONE LINK PER NODE, TWO ONLY AT THE CAPSTONE.** The
  selection is a breathing halo standing off the disc, a hard rim on it, and the chrome's corner brackets round
  that — **all three**, drawn last by the wheel itself so both screens get it.
- **THE BONFIRE IS A SCREEN, NOT A PAUSE** — he sits RIGHT, the menu is a list down the LEFT, and the wheel shows
  ONLY once Level Up is chosen. **GETTING UP IS A ROW ON THAT LIST, OR BACK**: "any button" cannot coexist with a
  cursor, and Back is the one button that can never also pick. The book and the pause card are BOTH refused at a
  fire. **NO HINT ROW ON THE FIRE'S LIST**; the WHEEL keeps its hints, because LS/RS/zoom is not guessable.
- **THE VIEW IS PANNED, NOT SHEARED** (`game.restCamera`) — eye and target move by the same vector along the
  camera's right axis. Screen-right is `cross(forward, up)`, `camera.rightXZ`'s law.
- **LEFT STICK WALKS THE WHEEL, THE CROSS ZOOMS, THE RIGHT STICK PANS.** Zoom is on the CROSS, not the bumpers
  (those are the book's page turn), which is why the cross is WITHHELD from the walk on a wheel and kept on a list
  — `menu.navFor` is that decision, in one place. **A stick is a LEVEL where a walk wants EDGES, and there are
  FOUR STANDARD PIECES, all here**: a RADIAL magnitude never per-axis (a square's corner passes at 0.62 per axis
  while true deflection is 0.88), a SCHMITT TRIGGER (`STICK_FIRE`/`STICK_REARM`), DAS then ARR, and a DEAD CONE AT
  THE DIAGONALS — **on a LIST or a GRID, which is the only place it belongs.**

## Armaments

**R1/R2 (and L1/L2) BELONG TO THE ARM, NOT THE WEAPON.** Attack buttons are read as buttons and routed by which
armament is in that hand: L1 is the left hand's ACTION (block / cast), L2 its SKILL (aim / parry). Swaps: D-pad
Right / Q = sword ↔ bow, Left / F = shield ↔ wand, Up / G cycles MEMORIZED sorceries in rack order. **A SELECTED
VARIANT IS LATCHED WHERE THE COMMITTED ACTION STARTS**, the selector REFUSES while one runs, and **one place
answers what it costs** (`combat.spellFp`) — exhaustive switches, so a new one is a compile error until it has
said what it costs and what it does.

**BARE IS THE GAME EXACTLY AS IT WAS** — every dial on an `item.Arm` defaults to 1 and the armour curve of 0
armour is the blow itself. A new game is bare-handed.

- **ONE TABLE, ONE ROW PER THING** (`item.equip`) — the numbers are all any of them is. The bag panel prints the
  row, **A CLAUSE PER DIAL** rather than a sentence per combination: four dials on a `Plate` is sixteen sentences.
- **A WEAPON IS PRICED AS MULTIPLIERS ON THE ARMAMENT IT FILLS, NEVER AS FRESH ABSOLUTES** — `hero.ATK_*_HIT`,
  `combat.STAM_*` and `GUARD_*` stay the one place a swing, a block and their bills are written down. **THE DIALS
  ARE NOT ALL THE SAME WAY UP**: `dur` and `stam` are BILLS, so under 1 is the gain there.
- **A WEAPON SAYS WHAT KIND IT IS ON TWO AXES** (`item.Heft`, `item.Reach`) — REACH pinned to the socket at
  comptime, HEFT how much of the body goes into it, and HEFT is what the page prints.
- **THE STROKE IS ONE STROKE, SCALED** (`hero.Move`/`moveOf`, three multipliers) — a club gathers further back,
  drops lower in the hips, carries further through; a dirk is the same stroke shut down to the elbow. **THE PLAIN
  SWORD IS 1 ON EVERY DIAL**, and a test pins the table against `heft`. **THE CLOCK MOVES WITH THE WEIGHT**
  (`atkDur`), and the POSE reads the same clock.
- **WHAT A ROW DOES TO A BLOW IS ONE FUNCTION** (`hero.weigh`), asked by sword, bow AND book — the ELEMENTAL half
  rides the damage dial and the STANCE rides the poise dial, and tallow is applied AFTER the row.
- **A SKILL DRIVES A BLOW THROUGH THE DAMAGE DIAL AND NOTHING ELSE** (`stats.scaleFor`) — one curve for
  strength/dexterity/intelligence, ER's 20/55/80 caps, and **1.0 at `stats.START` exactly as the bar curves are**,
  which is the licence for wiring damage to an attribute without retuning a tuned constant. A weapon names ONE
  skill; poise and stance stay the WEAPON's mass. **An EMPTY socket gets `item.bareArm`, not `Arm{}`** — the
  sword's `quality` default inherited by a bare bow paid a bowman for strength.
- **ARMOUR IS THE FIFTH COLUMN AND IT IS A CURVE** — worth most against small blows and least against the one that
  was going to kill you, so it can never become immunity and needs no cap. PHYSICAL ONLY, and it touches NEITHER
  POISE NOR STANCE.
- **A PLATE MAY MOVE HIM TOO** (`Plate.move`) — multiplied onto the tree's node in `hero.moveRateOf`, which
  `game.moveHero` is the only caller of, so a shoe that hurries him cannot reach one movement path and miss the
  others. **STRICTLY WORSE ARMOUR ON PURPOSE** where it buys a column and a pace: a piece better on every dial
  retires the one beside it instead of competing.
- **A SOCKET MAY BUY A SKILL** (`item.Boon`) — folded onto the live sheet by `hero.boonsOnto` through
  `hero.resheet`, which is THE place the sheet is built: the tree plus what he has on. `applyPerks` assigning the
  sheet straight from the bonus is how a belt got wiped off it by buying a node. A boon of an INERT attribute is a
  compile error.
- **EVERY SOCKET ON THE DOLL IS REAL, AND A COMPTIME WALK KEEPS IT THAT WAY** — `item.zig` fails to compile if a
  non-hand `Wear` has no kind that goes in it, and `book.wearOf` is the ONE place a doll slot becomes an
  `item.Wear`. A faint socket is a fact about his BAG, not about the world.
- **A SOCKET REFUSES WHAT DOES NOT BELONG IN IT** — `hero.wear` and the save's parser both ask `item.wearSlot`.
  Seated wrong, every dial reads as 1 and the piece silently does nothing.
- **A CHARM RESIZES THE RED BAR, AND THE FRACTION IS KEPT ACROSS THE RESIZE** (`refitHp`), through `hero.wear` and
  not at the next bonfire.
- **THERE IS ONE OF EACH, AND THE RACK IS FOUR CELLS** — taking a thing already racked SWAPS the two cells rather
  than refusing. **THE CELL DRAWS WHAT IS IN IT, NOT WHICH ARM IT IS** (`heldGear`). **THE VARIANT IS NOT REFUSED
  WHEN THE HAND IS** (`game.takeHand`): a socket left saying "club" over a fist still swinging a sword is the page
  lying. Saved as one `worn:` line, ABSENT from an older file, which loads as bare.
- **BOTH PAGES SPEAK IN NUMBERS, AND NEITHER CARRIES A BILL** — the rows are what the FIGHT uses: light and heavy
  through `weigh`, the clock in SECONDS, the guard's real negation, the arc in degrees, armour AND what its curve
  turns aside, the pools, the four columns. **A DIAL IS NOT A STAT**: "78% swing time" asks the reader to hold a
  number no page ever showed them. The stamina POOL stays, because a pool is not a bill.

**The book** (`book.zig`) — ER's status screen, read in sections.

- **THE PICKER ROW SAYS WHAT IT IS WORTH BEFORE IT IS PICKED** (`headline`) — the biggest thing the swap moves on
  the derived sheet, as a share of what it is now, signed and named short, in the colour of the news.
- **THE COMPARE IS FOUR COLUMNS UNDER SECTION HEADS** — NOW dim, a chevron when it moves, THEN in green or red
  (`cost` rows flip the colour), the signed difference at the edge. `GDial` lists the dials in section order and
  `gsectionOf` is an exhaustive switch, so a dial without a home does not compile and one pass inserts the heads.
- **ON THE SHEET is the swap priced in HIS numbers** — every derived figure that MOVES, so a boon's +3 Strength is
  read as the attack it buys. **A DIFFERENCE IS A WHOLE UNIT**: half a point or a hundredth of a clock is drift,
  printed as no change — never "10 → 10, +0".
- **BROWSING THE DOLL SHOWS THE PIECE *AND* THE SHEET** (`browsing`, `drawGearCard`) — the card is the slot under
  the cursor, a bare hand included, and a slot with no gear at all gives the sheet the whole column back. Capped
  at what the sheet is owed (`derivedNeedH`), `pickBox`'s own rule.
- **THE SHEET IS TWO COLUMNS AND THE ENUM'S ORDER IS THE LAYOUT** (`DER_SPLIT`) — what he DOES before the seam,
  what he IS after it; `rowStep` will not pitch under `rowFloor`, so one column of 21 rows drew over the panel.
- **A WEAPON'S FOOTER IS THE HALF A NUMBER CANNOT SAY** (`armWords`) — heft, reach, and WHICH SKILL DRIVES IT.
  **A BOARD PRICES NO BLOW**: the card and the compare read offence rows off a socket that actually swings.
- **THE PICKER OFFERS BOTH AXES AS ONE LIST** (`book.Hand`) — every armament, and under each the gear he is
  CARRYING that fills it, so the row is COUNTED rather than taken as an ordinal. **The VARIANT is the
  ARMAMENT'S, not the hand's.** **THE THREE MELEE SOCKETS RUN BACKWARDS TO A `Blade`** (`bladeForWear`), pinned
  against `wearFor`+`bladeOf` at comptime or a club is clocked as a sword.
- **THE STATS PAGE IS FOUR PANELS** — ATTRIBUTES (each point-count beside what it buys, the cursor row ending with
  what the NEXT point buys), BODY, WARDS (read off `ptree.Bonus` itself, so a node the tree grows tomorrow shows
  up here without a hand), and the portrait. `StatList` builds a column first and draws it after, into its own
  store: `hud.fmt`'s ring is sixteen deep and a column is longer.
- **THE PRIMS ARE `uiart`'S** (`rule`, `arrow`, `pill`, `meter`); text stays in `book.zig`, because `uiart` does
  not import `hud`.
- **NEITHER PURSE IS ON THE TAB STRIP** — souls AND gold sit under the portrait on STATS and at the foot of the
  doll on EQUIPMENT, the only place a total is stated. **THE GOLD PURSE IN THE BAG IS A MIRROR, NOT A STACK**:
  gold is a `u32` on the hero and the bag's counts are `u16`, so the inventory cursor is one past the bag's own
  ordinal (`bagAt`, `bagCells`, `heldOf`).

**The bow, the wand, the spells, the torch** (`hero.zig`).

- **THE SHIELD GOING IS ANATOMY, NOT A BALANCE DIAL** — `canGuard` ASKS the arm rather than the swap clearing a
  flag, and the HUD's LEFT slot goes EMPTY. **IT IS THE SKELETONS' BOW**: `archer.bowMesh`/`poseBow` shared and
  every stance angle lifted from `archer.poseUpper` — the one import running against the grain (hero → archer).
- **THE AIM IS HELD, THE LOOSE IS THE ONLY COMMITTED PART.** **AIMING SUSPENDS THE LOCK OUTRIGHT**
  (`game.activeLock`) — suspended, not dropped; R3 is dead while the bow is up, and it slows the look.
- **A BOW CHIPS; IT DOES NOT WIN** — both shots come in under the melee they compare to, poise slighter still.
  **ARROWS ARE FINITE** (ten plain, five fire), refilled at a bonfire, checked BEFORE stamina is charged, and the
  SELECTED kind is what flies, empty or not, LATCHED at `startShot`. **THE FIRE ARROW** hangs fire worth
  `FIRE_ARROW_FRAC` of the shaft's physical ON TOP of it — PoE2's "adds X fire damage", physical untouched.
- **THE SHOT CONVERGES ON THE RETICLE, it does not run parallel to it** — thrown at a point ON the camera's centre
  ray at the distance that ray REACHES. **THE AIM PUSHES THE EYE IN PAST HIM AND FADES HIM OUT**: the player's own
  `dist` is never written, and the fade is LIT-PASS ONLY with the depth mask off.
- **HIS SHAFTS ARE A PIERCING BLADE** (`Blade.pierce`), which neither reads nor writes the swing latch. **THE BOLT
  FLIES THROUGH THE ARROW POOL** (`archer.Shot.bolt`) — cover, gravity, ground, expiry and the swept `pierce`
  test are one body of code.
- **A CAST IS COMMITTED, NOT HELD** — the FP is gone the moment it starts, so it lives in `committed()`, is not
  buffered, and a stagger drops it with the charge spent. He is PLANTED for it. **PAY OR CAST NOTHING**
  (`Focus.spend`), the INVERSE of stamina's panic rule. **BILLED IN FP AND NOTHING ELSE** — the wand competes with
  the flask, not with the roll. **ALL CHAOS, NO PHYSICAL**: chaos is the most-resisted column, so the wand answers
  toads and kobolds and is near useless against skeletons. An honest trade.
- **THE ARM GOES OVERHEAD AND SWEEPS ACROSS THE TOP**, repeated casts sweeping OPPOSITE ways — `rz` swings the
  left arm through the frontal plane and 180 is straight up, so raise and stroke are ONE channel. **THE ARM GOES
  LONG AT THE THROW**: a folded elbow keeps the stone inside his own silhouette. **THE ROD IS NOT A BONE** and has
  no fit matrix — authored in the left wrist's frame along −Y, and `wandTipWorld` is MEASURED off the mesh's own
  constants (the ogre's `clubLowWorld` law).
- **THE STONE IS THE ONLY LIGHT IN THE GAME THAT MOVES** — `env.uploadLights` takes it as a RESERVED slot (beside
  the torch's), so a brazier he stands beside can never evict his own spell.
- **THE GATHER RIDES THE HAND AND ITS LIFE IS WHAT PAYS FOR IT** — motes solved to ARRIVE at the stone. Adding the
  tip's velocity fixes the constant part; the leftover is ½·a·life², so the correction that matters is a SHORT
  LIFE — and `drawParticles` fades radius with alpha, so **a short life is bought back with RADIUS, never with
  more motes.** **THE RELEASE IS A CONE, A COLLAR AND ONE FLASH**: the cone alone is indistinguishable from the
  bolt's first metre, and the collar thrown sideways is what says the stone LET GO.
- **THE CHARGE RISES IN THE GRIP, AND A `rumble.Event` CANNOT RISE** (a `Motor` decays from its peak) — so the
  raise is pulsed every frame with a peak scaled by `chargeFill`, 0 past the throw.
- **THE LADDER IS MONOTONE, AND THAT IS THE WHOLE PRICE LIST**: bolt 8, levin 11, roots 12, siphon 13, lance 14,
  rime 15, sunder 16 FP. **Every step up in FP is a step DOWN in raw damage** — what the difference buys is a
  stagger, a hold, HP back, or a second body in the cone. A comptime block asserts it over every PAIR, so an
  eighth spell is priced by the rule without editing it. **ONE PLACE ANSWERS WHAT A SPELL LANDS** (`spellBlow`),
  null for the two that bill over time.
- **LEVIN AND SIPHON DO NOT CROSS THE GROUND** — they arrive on ONE body on the frame they are cast, and SIGHT
  stands in for a flight. **THE LEVIN BUYS THE STAGGER AND NOTHING ELSE** (poise 34, past every `POISE_MAX` bar
  the knight's 78; its STANCE stays under his own heavy swing's). **IT DOES NOT TRAVEL BECAUSE THE ELEMENT DOES
  NOT** — the travel comes from WHERE THE SPARKS ARE PUT, laid along the blow's own segment on the landing frame.
  **THE STROKE LEANS, AND THE LEAN IS MECHANICAL** (`game.strikeSegment`): `foe.strike` takes the shove and the
  facing snap off the segment's XZ bearing, and a plumb line has none.
- **THE SIPHON FEEDS OFF WHAT THE BODY ACTUALLY LOST**, never off what was thrown at it — so resisted damage is
  resisted healing and a skeleton is a bad meal. **IT IS A DRAIN, NOT A BLOW**: no poise, no stance.
- **THE MEMORY RACK IS THE ONLY LIMIT, AND IT IS ONE NUMBER** (`MEM_SLOTS`, three) — a new character has the bolt
  and two holes. **CARRYING THE SCROLL IS THE WHOLE GATE, AND MEMORIZING DOES NOT SPEND IT.** **THE RING IS THE
  RACK, NOT THE TABLE** (`Memory.next`) — D-pad Up walks what is memorized IN SLOT ORDER, and a spell already in
  another slot MOVES rather than doubling. **THE SELECTION IS A FINGER ON THE RACK AND FOLLOWS IT** (`hero.armed`,
  `tidySpells`; `memorize` is the ONE door that moves either). **THE FIRE IS WHERE IT IS COMMITTED AND THE BOOK IS
  WHERE IT IS READ** — the fire's screen is two stages, the equipment picker's exactly, opening on WHAT IS IN THE
  SLOT. A sorcery he has no scroll for is DIMMED, never hidden. **THE FILE CARRIES THE RACK AND NOTHING DERIVED.**
- **THE TORCH IS A RACK CELL, NOT A KEYBIND**, and **WHAT IT COSTS IS THE HAND, AND NOTHING ELSE** — no stamina,
  no FP, no action on either button. **THE FLAME IS DRAWN IN WORLD SPACE, THE BRAND ON THE WRIST**: the shader's
  billow throws along the MODEL's +Y, so hung off the wrist it would lash sideways when he turns his arm over.
  **THE CARRY WAS SOLVED, NOT EYEBALLED** — flame at the crown, off the shoulder line, in front of the chest, and
  the test prints all four figures with a window round each. **IT GUTTERS OFF THE SAME CURVE AS EVERY OTHER
  FLAME** (`mathx.gutter`, three incommensurate rates). **ITS VOICE IS A BED, NOT A PLACED SOUND** — nine pops a
  second, redrawn every pop: a crackle is Poisson, not a metronome.
- **THE HARNESS HAS TO FIRE THE RELEASE ITSELF** — `castToThrow` drives the POSE past the throw without going
  through `game.throwBolt`, `castToCharged` stops one frame earlier (the only frame the gather's ramp and the
  light's swell can be judged on), and `game.selectSpellForShot` MEMORIZES rather than cycles.

**Souls — the drop, and the ring that refuses it.** Everything comes off him on the frame he DIES rather than at
the respawn, so the spill plays under the YOU DIED card.

- **THERE IS EXACTLY ONE** — a second death overwrites the first. Not a storage decision: a list of drops would
  delete the whole risk. **NOTHING ELSE SPENDS IT** — no timer, no decay, no despawn on distance; a death
  RE-HOMES the field and must not touch the drop, and only a change of MAP clears it.
- **RETRIEVAL IS INSTANT** — no committed action, no animation on the man. The animation is all on the DROP, motes
  solved to ARRIVE at his chest inside their own life.
- **IT IS A TREE, NOT A FLAME**, so it obeys the dead-limb law, and it grows over `RISE`, overshoots its own height
  and settles. **ONE EMISSIVE LEVEL, THREE ALBEDOS** — vertex alpha is the emissive channel, so all three golds
  sit at one alpha and separate on hue and value alone; at two levels the shaft bands.
- **THE PROMPT IS FIRST IN `game.reachable`**, ahead of the fire, the folk and a box, and its ring is the GENEROUS
  one — `souls.REACH` against `chest.REACH`, asserted at comptime.
- **THE SOUL BINDING RING REFUSES THE WHOLE THING** (DS's Ring of Sacrifice) — worn, a death takes the RING
  instead of the souls. **IT HAS TO BE ON A FINGER**, the FIRST ring socket, the leech signet's own, so the choice
  is HP back on every landed blow against keeping what you carry the once. **IT IS NOT A TOOL** — `usable` false,
  off the quick bar: the one piece of gear spent by DYING. **ASKED OF THE ITEM, NOT THE KIND**
  (`item.bindsSouls`, off the `Bind` payload), which is why `game.bindingWorn` walks every socket. **ONE IN THE
  WORLD**, and the BONE KNIGHT carries it — nothing places it.

## The world

### The map is data, and the editor owns it

`worlds/*.world` are versioned text files of authoring OPS (`worldfmt.zig`); `env.materialize` replays them.
**Nothing about the world is authored in Zig.** Ops: `at`, `belt`, `disc`, `ring`, `line`, `ivy`, `edge`, `cover`,
plus `zone`/`clear`/`runway`/`foe` tables. The world is **1000 m**.

**`worlds/test_*.world` ARE BENCHES, NOT CONTENT** — one per thing being built, loaded with `--map
worlds/test_x.world` (and `--shot` with it). **NOTHING UNDER TEST GOES INTO THE SHIPPED MAP TO BE LOOKED AT**,
and never pin a test to a coordinate, yaw or count off `01_fallen_plain.world` — author a bench instead.

- **ONE FIELD TABLE DRIVES THE WRITER AND THE PARSER** (`fieldsOf`), walked at comptime in TABLE order —
  `std.meta.fields(Op)` reads the STRUCT's order and silently writes the wrong column. Unknown keys and missing
  fields are LOAD ERRORS; a missing or broken map PANICS with file and line.
- **ORDER IS MEANING** — ops replay in file order because later ones read what earlier ones placed.
- **EVERY GENERATOR OP CARRIES ITS OWN SEED** — one shared stream meant inserting a belt re-rolled every op after
  it. Load-bearing.
- **A GENERATOR OP IS FOR STAMPING, NOT FOR KEEPING** — it is ONE thing to select, move and delete, so a wood of
  260 attempts was one tree. Stamp, re-roll until it reads, then **break it apart** (`env.explodeOp`) and it
  becomes one `at:` per instance standing exactly where it stood, since an `at` replays at the same
  `groundY(x, z)` every generator plants on. There is no way back but undo. `--explode <map>` does a whole file
  headlessly and verifies by re-loading: same prop, solid and light counts or it refuses. **`01_fallen_plain` IS
  ALREADY BROKEN APART.**
- **AN OP MAY NOT SPIN** (`Placer.BUDGET`, `Env.opsCapped`) — the generator loops were bounded only by AUTHORED
  numbers and a REJECTED candidate costs time without ever filling `MAX_PROPS`. One line op at 0.001 m over 400 m
  burnt **21 ms a rebuild placing NOTHING** (227 ms at the parser's floor), a rebuild fires after every edit, and
  a map holds 40,960 ops. Every generator now spends from a per-op candidate budget. **NO SILENT CAP** —
  `opsCapped` counts what hit it and the editor's status line shows it, because a budget that bites real content
  has made the world quietly smaller.
- **EVERY PROP PLANTS AT THE HEIGHT UNDER IT** — `uploadHeight` must run BEFORE `materialize`, and a sculpt stroke
  re-materializes on RELEASE. **`buildSolids` RESETS** (`materialize` runs it twice; an appending version doubles
  every collider). Props carry the index of the op that placed them, which is what makes a generated rock
  selectable. **PROPS CAN LEAN** about the prop's GROUND ORIGIN, so the base stays planted and the culling sphere
  is unchanged. **AND `env.build` MAY RUN ONCE PER PROCESS** (`envBuilt` panics on the second).
- **A MULTI-LINE RECORD ATTACHES TO THE ONE ABOVE IT** — `when:`/`do:` to the last `trig:`, `who:`/`say:`/`act:`/
  `then:`/`ask:` to the last `node:`, `need:`/`gets:` to the last `ask:`. A part with nothing above it is a LOAD
  ERROR, and `act:` may not be written after a choice. **PROSE LIVES IN ONE ARENA** (`Map.dtext`, `Span`), and `#`
  still starts a comment, so no authored line may contain one.
- **`npc:` RECORDS ARE APPENDED, NEVER INSERTED** — `near npc=0` is an INDEX into that table. `foe:` and
  `wf.FoeKind` have the same rule. **AND A MAP SAYS WHERE THE PLAYER STARTS** (`wf.Start`, the `start:` row).

```
flags: met_wanderer heard_of_gate      # interned at load; the file stays self-describing
npc: wanderer -4.50 7.50 128.0 1.00 0.31 roam=1.8 dlg=wanderer
  call: The Wanderer
dlg: wanderer
  node: root
  say: Another one walking north.
  ask: What lies north? -> north
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

Conditions: `always`, `never`, `flag N=0|1`, `counter N <cmp> n`, `timer N=done|running`, `elapsed <cmp> secs`,
`region x z x1 z1`, `near npc=i r=m`, `talked dlgId`, `deaths foeKind <cmp> n`, `alive foeKind <cmp> n`. Actions:
`dialog dlgId`, `text …`, `flag N=0|1|flip`, `counter N set|add|sub n`, `timer N=secs`, `wait secs`, `preserve`.
`<cmp>` is `<` `<=` `=` `>=` `>`.

**The editor.**

- **EVERY NUMBER IS A TRACK AND A CLICKER, AND THEY ARE ONE WIDGET** (`ui.stepperF`/`stepperI`/`slider` all reach
  `ui.gauge`) — one `ui.ROW_H` row: the label rides a bar that sweeps the whole range, the `-`/`+` beside it walk
  one `step`, and a swept value lands on the same lattice a clicked one does. A click alone never moves it
  (`ui.DRAG_PX`), because the label sits on the bar. **AN ANGLE TAKES `ui.angleF`** — one turn, wrapping — never a
  stepper over `-360..720`, which is a track nobody can aim. `ui.track` is the bar on its own, for a panel that
  draws its own readout (`tuneui.dial`).
- **EVERY PANEL EDIT BANKS ONCE A GESTURE, NEVER ONCE A CLICK** — `Editor.bankGesture` for a number,
  `bankWorld`/`bankOpGesture` where the edit spans more than one record, and `bankTyping` for a name, which
  answers on every frame the buffer differs from the record. A bare `bank` inside a widget's `if` fills a
  24-slot ring with one rename. The gesture ends on `!ctx.down`, ONE place per panel.
- **BOTH SIDE PANELS SCROLL** (`beginScroll`/`endScroll`) — the Ground layer alone lays out 1038 px of brush
  strip in a 704 px panel and the last nine tools could not be clicked. A list inside one owns the wheel over it
  (`ui.Ctx.wheelTaken`), and a scrolled panel scissors its POINTER as well as its drawing (`ui.Ctx.clip`), or the
  rows above the top keep taking the clicks.
- **THE UNITS LAYER MARKS BOTH KINDS IN ONE LIST** (`NPC_MARK`, a folk is its index past `wf.MAX_FOES`) — the
  same address `hoverInLayer` uses. Marking creatures alone, the marquee still said "{d} selected".
- **THE UNITS PALETTE IS TWO TABS AND THE FOES ARE FILED BY KINGDOM** (`editor.UnitTab`, `foe.homeOf`) — 41 icon
  rows in one column is 1220 px of list in a 738 px panel, so the bottom seventeen creatures could not be clicked
  at all. Foes / Folk, and under Foes a chip per `props.Biome` that holds one — the same axis the props are filed
  on. `foe.homeOf` is EXHAUSTIVE and **NOTHING SPAWNS BY IT**; `any` is not a dustbin, it is the set that answers
  every chip, which is why it has no chip of its own.
- **THE DIGIT KEYS AND THE PANEL WALK ONE LIST** (`visibleBrushes`) — filtered in one and not the other, `3` armed
  a creature the palette was not showing. The eraser is in every tab, and the tab moves to the armed brush on
  entry, never the brush to the tab.
- **THE CRIB NAMES EVERY GESTURE, OR THE VERB DOES NOT EXIST** (`editor.CRIBS`, widest-that-fits) — it named eight
  while the editor bound twenty-five. **The EDITOR is the one place the UI names KEYS.** The Caves layer has its
  own list (`CAVE_CRIBS`), because its verbs are an ORDER and not a keyboard. A brush LABEL may put a space where
  its enum tag has an underscore ("Roof up" is `roof_up`) and `pinNames` allows exactly that and nothing else.
- **EVERY REGION IS SELECTED, MOVED, RESIZED AND NAMED THE SAME WAY** (`Grab`, `pickRegion`, `dragRegion`) — one
  union rather than a flag per kind, handles drawn as posts, banked on the first frame a drag moves something so a
  plain selection click leaves no undo step.
- **RESET IS THE ONE STROKE THAT TAKES A PATCH BACK TO BARE FLOOR** (Ground > clear > Reset) — height to the datum
  with NO feather (a graded rim is more terrain to undo, not less), the cliff flags, the cave, the water, the
  soil, and every op, foe and folk anchored in the disc. Zones, locations, arenas and clearings survive it,
  because a disc cannot say which part of a rectangle to take.
- **THE DECOR LAYER IS NOT PLANTS** — it is `props.Info.flora`, which holds cobbles, shards and scree too.
- **THE MINIMAP IS FIVE THINGS** (owner) — walls, water, trees subtly, fires, red for the foes. **A wall is
  whatever the camera will not thin** (`Info.solid`), the same set the hero cannot walk through, so the map's
  barriers and the world's cannot drift apart. **Read off `env.placed()`, never off the ops**: a belt of a hundred
  trees is ONE op, and an op walk drew one tree where there is a wood.
- **A PANEL MAY NOT SPEND A DRAW CALL PER OP** (`blitMinimap`, `miniGen`) — it issued **16,510 immediate-mode
  rects a frame**, and the bill GROWS every time a scatter is exploded into `at:` ops. Those ops land on 12,442
  distinct pixels of a 182x182 face, a 1.33x collapse, so no bucketing makes a per-frame walk cheap and the
  answer had to be a HELD TEXTURE, painted on `miniGen` and blitted once.
  - **A HELD FACE IS COPIED BACK, NOT BLENDED BACK** — raylib blends the target's OWN alpha by `SRC_ALPHA`, so
    every translucent thing painted in drives the target's alpha below 1 and blending that over the panel
    multiplies the face a SECOND time. Blit with `rlSetBlendFactors(GL_ONE, GL_ZERO, GL_FUNC_ADD)`.
  - **AND THE SAME LESSON REACHES A BUTTON'S LABEL** (`unfilledCount`) — "next empty (N)" walked all 40,960 ops
    every frame the Interact layer was open. Held against `miniGen` it is 0.002 us, and a test fills without
    banking to prove it is a CACHE and not a second walk.
- **THE CHART IS TWO HELD SHEETS AND A LENS** (`ui/mapart.zig`) — the map painted ONCE into a 2048 texture in
  world space and the fog into a 128 one; the lens only blits a sub-rect of each, and walls are drawn as the
  COLLIDERS with all haloes before any fill.
  - **THE MASK IS BINARY AND THE PICTURE OF IT IS NOT** — one bit a 7.81 m cell blown up through a BILINEAR
    filter, which is what makes the reveal a soft disc rather than a staircase. Punched with `GL_ONE, GL_ZERO`.
  - **REVEALED ONCE A CELL, NOT ONCE A FRAME**, after the gates and the room have had their say, CAPPED at the
    sheet, seeded at the spawn. Saved as `seenmap:`, the widest row the file has.
  - **AND IT IS WHAT HE HAS SEEN, NOT WHERE HE HAS BEEN** (owner: you have to see the other side of a wall to map
    that side) — every unrevealed cell in the disc costs one `env.sees` from his EYE down onto the ground out
    there, and the look STOPS SHORT by `NEAR_FACE` (half a cell) so the wall's own cell charts and the ground
    behind it does not. The `self.cell[i]` test comes BEFORE the look, so re-treading known ground pays nothing.
    Every solid blocks, not only the wall-marked ones, so a wood charts speckled and fills in as he moves.
- **THE THIRD FIELD SKIPS TOO** (`env.uploadSoil`) — `uploadHeight` and `uploadWater` each compare before they
  rebuild; soil alone re-uploaded three textures and re-ran a 12,544-cell edge dilation on every edit.

### Flooring, coasts and liquids

- **FLOORING IS TWO GRIDS** — `soil` (material id) and `soilCov` (coverage 0..255); an edge is where the author
  left coverage low. The paint rule is `lerp(here, opacity, falloff)`: painting below what is there THINS it and
  repeated passes converge. A cell holding a different material is CONTESTED — the stroke wins only where it would
  cover more. **A CELL IS 5 m**, the floor on how fine any of this can be: warps under about half a cell do not
  survive the coverage staircase.
- **HOW A PATCH ENDS IS PAINTED, NOT DERIVED** — a third grid (`Map.soilEdge`, one `wf.Edge` per cell), picked in
  the brush panel like radius and opacity, and it is the STROKE's, not the material's. Eight shapes (`blend`,
  `natural`, `frayed`, `jagged`, `straight`, `tiled`, `scallop`, `speckle`) with their ordinals pinned to the
  shader's `edgeShape()` by a comptime assert.
- **AN EDGE HAS THREE KNOBS**: how far the lookup WANDERS off the authored line, at what WAVELENGTH, and whether
  the boundary CUTS or feathers. **The policy is read FIRST, at the unwarped position**, because the warp is what
  the policy decides.
- **THE EDGE MAP IS DILATED ONE CELL AT UPLOAD** — a boundary is drawn from both sides and the shader must read
  the same policy either way. POINT-sampled, for the id map's reason: a bilinear read halfway between `tiled` and
  `jagged` is an ordinal nobody authored.
- **THE COAST USES THE SAME EDGES, AND THE TABLE IS WRITTEN ONCE** (`shaders.EDGE_K`) — the GLSL `edgeShape` is
  GENERATED from that table and `shaders.warpEdge` is its Zig twin, so a shape means one thing whether it is soil
  or water.
- **THE SHEET DIES INTO THE SHORE; IT IS NOT CUT BY IT** — a domain warp whose amplitude beats its own wavelength
  FOLDS OVER ITSELF, and a hard threshold turns every fold into a shard. Soil never had this fault because its
  edge is an ALPHA; water was the one surface asked to end at a compare. **The amplitudes are the soil's own and
  are not the problem** — do not tune them to chase a hard edge.
- **THE COAST GETS A LOW OCTAVE THE SOIL DOES NOT** — bays at ~22 m, in METRES and not as a multiple of the
  shape's wander, small enough that a painted pond is still the pond somebody drew.
- **THE FIELD IS ONE FIELD, FEEDING THE LOOK *AND* THE WADING** — `shaders.waterAt` per fragment,
  `env.paintedDepth` per query, off the same row. Shaped only on the GPU, the coast you see would sit up to
  `warp` metres from the coast you walk into. **Anything that reads the field for gameplay goes through
  `paintedDepth` or it is looking at the wrong line.**
- **WATER IS PAINTED, ITS COAST DERIVED** — one bit per cell → a signed distance field (128 is the waterline). One
  field, three effects.
- **EVERY BODY CARRIES ITS OWN LEVEL** (`Map.waterBase`, a `Hgt` per cell; `wlvl:` row, absent = the datum) — the
  sheet stands `env.WATER_SKIM` (0.045 m) over it, and **EVERY READER ASKS `env.waterLevelAt`/`levelOf`**: the
  depth bake, `wadeDepth`, the pool floor (`dwellerFloorAt`), the face's wet band. A cell painted onto a body takes
  the body's base; the first cell of a new pond takes the ground under the brush. Ground > Level floods the
  connected body under the click (`Map.levelBody`). **THE SHEET IS ONE FLAT STRIP PER RUN OF CELLS AT ONE LEVEL**
  (`Env.sheetStrips`, rebuilt on every water upload) — two bodies at different levels meet at a step, never a
  slope. The lurker's band (`foe.poolBand`) is read off the same depth, so raising a body over 1.37 m of water
  drowns its lurker and the shipped-map test says so.
- **FOUR LIQUIDS, ONE SHEET, ONE FIELD** (`wf.Liquid`) — water, oil, fungal, lava, one per cell off the same
  brush. **THE FOOTING IS WATER'S AND UNCHANGED FOR ALL FOUR**: same coast, same `paintedDepth`, same `WADE_MAX`,
  same `Gait` gate, same `avoid.water`. **Three things differ and only three** — the LOOK, the STATUS it soaks in,
  and the VOICE.
- **THE KIND RIDES IN THE COAST BYTE** (`env.packLiquid`) — `wf.Edge` in the low three bits, `wf.Liquid` in the
  next two, one point-sampled `u8` per cell: they are dilated by ONE walk off ONE paint, and a second sampler
  would be an EIGHTEENTH texture unit where GL 3.3 promises sixteen. `liquidAt` reads the DILATED field, so a foot
  on the bank answers with the pool's kind.
- **A MAP WITH NO `liquid:` ROW IS ALL WATER** (ordinal 0), so every map written before this round-trips byte for
  byte. Same for `soiledge:` (`fillLegacyEdges`: stone cut, everything else soft; the row is only written when
  some stroke asked for something else).
- **THE STATUS IS A SOAK, NOT A BLOW** (`play/liquid.zig`) — the sporeling cloud's channel, so nothing blocks it
  and nothing parries it. **NOTHING DECAYS UNDER A CONTINUOUS DOSE**, so `max/build` IS the seconds to break:
  fungal 13.9 s of POISON, lava 7.0 s of BURNING, clipping a rim 2% and 5% of the bar. Lava also drips 4.5% of MAX
  HP a second in fire — a SHARE of the bar so a levelled body cannot walk it off, and a DRIP so it never builds
  the meter twice. Oil is a look and a sound and nothing else.
- **LAVA IS A LIGHT, NOT A SURFACE** (`sheetGlow`) — written from inside the sheet's material branch and applied
  past the emissive mix, because `emis` rides a vertex alpha a world-spanning quad cannot carry. It takes NO sun
  lobe: a specular streak on lava reads as wet plastic. **Tar's fresnel is the OPPOSITE problem** — at water's
  exponent 3 an oil pit came back a flat slate disc, because a sheen over a near-zero albedo IS the pixel. Fifth
  power, a third the amount.
- **BUBBLES ARE ONE HASH TAP, NOT NINE** — one per cell, centre in 0.3..0.7 and radius under 0.28, so a dome can
  never cross into a neighbour and the 3×3 ring is not paid for on a world-covering quad. They MOUND and then
  pop; the swell is most of the read.
- **ITS VOICES ARE A BED PLUS A THINNED POP** — one dialled bed per liquid (off a scan bounded to 27 cells a side)
  and a pop every ~1.15 s from a reservoir-sampled wet cell. **WATER GETS NEITHER**: the wind is its bed, and
  painting a tarn may not add a voice to a map that already sounded right.
- Benches: `test_wateredge` (eight ponds, one per `Edge`), `test_liquids` (one 14 m pool per liquid).

### Elevation

A HEIGHTFIELD sculpted in Ground > Raise/Lower/Smooth/Flat, stored as one QUANTISED height per lattice point
(`HEIGHT_N`, `HEIGHT_STEP`, biased so `HEIGHT_ZERO` is the old flat ground) — quantised because the file is TEXT
and the writer is a run-length encoder. The mesh is TILED, with normals from the FIELD so two tiles agree at their
seam.

- **A HEIGHT IS `wf.Hgt` (u16), −1024..+15359.75 m** — `version: 3`. A `version: 1` file's `hgt:` bytes are widened
  onto `HEIGHT_ZERO` as they are read, so the shipped map loads unchanged; a 3 on a build that knows only 2 is a
  LOAD ERROR, never a clamp. **THE CAVE FLOOR AND ROOF STAY ONE BYTE** (`CAVE_H_ZERO`, `caveH`/`caveByte`,
  −16..+47.75 m): the roof is a GPU texture the shader decodes, so a chamber cannot be carved under land above
  47.75 m. `heightByte` keeps its name and returns a `Hgt`.

- **A FLAT MAP IS THE OLD WORLD, EXACTLY** — `heightAny` false means one world-spanning quad, `groundAt` returns
  `GROUND_Y`, and no `hgt:` record is written.
- **NOTHING SAMPLES THE MAP DIRECTLY** — env keeps the live copy the visible mesh was built from and
  `wf.sampleHeight` is the ONE sampler both owners call. It reads the CLIFF grid beside the height, and a flagged
  cell steps instead of interpolating.
- **THE LATTICES GREW WITH THE WORLD**, rather than `half` growing on its own — `half` is a DIVISOR
  (`2 * half / (N - 1)`), so raising it alone stretches the sculpted land off the props standing on it. The test
  binary needs the exe's own 192 MB stack because a round-trip test holds two `Map`s in one frame.
- **AN OLD MAP EMBEDS EXACTLY, IT IS NOT RESAMPLED** (`wf.grownHalf`, `gridRead`) — every lattice gained the same
  number of points, so a legacy record grows the map's own half by that ratio and the CELL SIZE IS UNCHANGED.
  Worst height move on the shipped map: **0.000 m**. A bilinear resample was the first attempt and it blunted
  every authored step. `--grow <map> [half]` writes the migration down and refuses at more than one `HEIGHT_STEP`.
- **THE FLOOR IS A MARGIN ON THE LOADED MAP'S OWN HALF** (`env.groundOut`, `GROUND_APRON` 0.12 with a 60 m floor)
  — **AND IT IS A SKIRT, NOT A SECOND WORLD.** At 0.80 the shipped map drew 400 m of floor a body could see and
  never reach. The flat path draws ONE quad built at the widest and scaled (a plane scales exactly, and every
  field the shader reads over it is indexed in world xz).
- **TWO RULES DECIDE EVERY STEP** (`env.walkStep`): the rise ahead is within `MAX_SLOPE` (tan 40°), or it is under
  `STEP_UP` (two risers, three a wall) **AND LANDS ON A TREAD** (`treadAt`: a deck, a stair cell, or ground under
  `MAX_SLOPE` read a quarter-metre either way) — `STEP_UP` over the probe alone was a 47.7° climb. Read at the
  step's own end and at four taps along `STEP_PROBE`, because a probe that landed past the corner of a cut put the
  body on top of the wall.
- **MEASURED OVER A FIXED LOOKAHEAD, NEVER THE FRAME'S OWN TRAVEL** — against frame distance a 240 fps hero
  ratchets up a vertical cliff. A test pins the rule across four frame rates. **A REFUSED STEP IS NOT A STOP**:
  the uphill component is removed and the rest is taken at full length.
- **FOES GET THE SAME RULES as a POST-STEP GATE** (`game.gateTerrain`) — airborne foes are exempt from the terrain
  rule and from being shouldered, **never from `env.resolveActor`**, and that push-out is NOT rate-limited.
- **BUT NOT AT HIS WATERLINE — AT THEIR OWN** (`foe.wadeLimit`) — `WADE_MAX` is CHEST height on the 1.8 m rig and
  HIS choice; a creature turns back at `foe.WADE_FRAC` of its own stature, read off `topWorld`. **THE WATER IS A
  DOOR FOR EXACTLY TWO THINGS** — the gait table hands `.waterfaring` an infinite limit. The gate only refuses a
  step that goes DEEPER.
- **A WATER DWELLER IS POSTED IN ITS OWN BAND** (`foe.poolBand`) — the editor refuses a lurker outside
  `POOL_MIN`..`WADE_MAX` (place and paste both, and says why), and Ground > Pool digs to `env.dwellerFloor`, the
  deepest lattice height the hero still wades. **One place holds the band.**
- **`pos.y` IS THE GROUND UNDER AN ACTOR**, written in ONE place (`game.groundActor`), EASED not snapped because
  the camera rides the shoulder; past `GROUND_SNAP` it plants. **EVERY WORLD POINT ON AN ACTOR IS MEASURED FROM
  `pos.y`.**
- **THE CAMERA SHORTENS ITS BOOM RATHER THAN BURYING THE EYE** (`camera.followClear`) — **but it gives way to
  terrain only, never to its own pitch.** An up-tilt puts the eye LOW on purpose. Only ground standing PROUD of
  the hero's level is worth paying distance for. **THE BOOM IS SHORTENED AT ONCE AND GIVEN BACK AT A RATE**
  (`CLEAR_REGAIN`); the shot harness solves fresh, because a shot has no previous frame.
- **THE HERO LEANS INTO THE HILL** (0.55 of the slope capped at 16°) through the SAME `rx(bodyPitch)` term as the
  run lean.
- **THE TERRAIN CASTS FROM ITS FAR SIDE ONLY** (`env.drawGroundCasters`, FRONT faces culled) — drawn whole, a
  heightfield off a 108 m ortho box put acne everywhere the surface grazed the sun. Only triangles facing AWAY
  from the sun write depth: the lit slope never meets its own depth, the far slope is the silhouette that throws,
  and the seam between hill and cut is gone. **THE PAINTED CLIFF FACES CAST TOO** (`env.drawCliffCasters`) — the
  SHEET off a PLATE set inside the rock and under the lip, depth pass only, both windings; **EVERYTHING STOOD
  AGAINST IT CASTS AS ITSELF** (`Face.cast`). Moss and grass tufts do not cast. The tile cull hands `castsInto`
  the tile's own height, so a tall face just outside the box still throws into it.

### Cliffs — a drop drawn as a FACE instead of a ramp

A second grid (`Map.cliff`, one case per CELL, indexed by its low corner) says which cells cut instead of
interpolating. Ground > Cliff paints it, Slope takes it back. **4..255 ARE UNCLAIMED** and a map using one is a
LOAD ERROR on a build that does not know it — which is what `wf.VERSION` 3 bought when `CLIFF_FALL` took 3.

- **THE FLAG IS OPT-IN AND CHANGES NOTHING ELSE** — no `cliff:` row means the map loads and walks exactly as it
  did. The same 6 m drop is a wall or a ramp depending on the flag, not on how steeply it was sculpted.
- **ONE CUT SERVES THE MESH AND THE SAMPLER** (`wf.cliffCut`) — marching squares on the cell's four corners
  against the midpoint of its two tiers, **crossing every cut edge at its MIDPOINT**, the one place both cells on
  that edge agree. **THE FLOOR EITHER SIDE IS THE TERRAIN, NOT A TIER**: each side walks the bilinear of its own
  corners, a corner across the cut standing in at the level its neighbours on this side hold. Snapped to `lo`/`hi`
  instead, the walk stepped at every seam — 67 steps in 75 m along the shipped lip, 20 of them falls.
- **A SADDLE'S MIDDLE IS A TIER, NOT A HOLE** — the bilinear's own centre decides which tier fills the diamond,
  and the two chords that then face the other way get the wall.
- **PAINT UNDER A WALKABLE DROP IS INERT** (`wf.cliffMinDrop` = max(`STEP_UP`, `MAX_SLOPE`·cell), 2.1 m) — a
  painted cell cuts only where a ramp over it could not be walked. **Paint generously; it costs nothing.**
- **A LIP IS WALKED ALONG, NOT WALKED OFF WHERE HE IS STOOD** (`game.brinkStep`) — the step's share toward the
  drop is removed and the rest taken along the lip, the way the walk gate treats a rise. A body DROPS a lip under
  `DROP_FRAC` of its own stature when the hero stands below it, which is a position read and legal.
- **THE FACE IS THE PROPS' OWN ROCK** (`env.cliffWall`) — one flat plate per cell was the Minecraft read. A face
  is a lattice of spans by courses, bellied over the low ground and swept by a 9 m bay field; `blocky` sets how
  proud the strata stand (keyed on WORLD height, so a course runs level through every cell), `cleft` the grooves,
  `ivy` the curtains, `broken` the talus. The kind is a 27 m field, so a run reads as one geology. **THE LIP IS
  STRAIGHT AND THE CUT IS EXACT** — a ±0.3-cell wander made every straight line an accordion of facets.
- **AND THE FACADE IS ROCK STOOD AGAINST IT, NOT A BISECTED CLIFF PROP.** The wall is a PLAIN SHEET on the cut, lip
  and foot on the two floors at the chord's ends so it runs with sloping ground (a test measures its area against
  the cut's own to 1%), and the rock is `proprock.faceRockBuild` — a 2.4-4.4 m mass, its own size, never the
  drop's — stamped by `env.faceStamp` in a LATTICE: a column every `FACE_ROCK_RUN` of run, a row every
  `FACE_ROCK_RISE` up the face, each sunk until `FACE_ROCK_PROUD` of its own depth stands in front of the cut,
  **EVERY ONE SPREAD PER STAMP** (`FACE_ROCK_TURN`, `FACE_ROCK_DRIFT`, `FACE_ROCK_SCALE_VAR`) or a column reads as
  a stack. **NOTHING IN THE FIT READS THE DROP** — the same stone dresses a 2 m face and a 12 m one, and only the
  ROW COUNT changes; a rock cresting past `FACE_ROCK_CREST` over the lip is dropped so the plateau stays a
  straight line, and one last rock is hung with its crown ON the lip to close the bare band the rows leave. **THE
  SHEET IS DIMMED UNDER THEM.** **EVERY LOBE THAT STANDS PAST THE CUT IS SOLID** (`stampSolids` →
  `Env.cliffSolids`), one capsule along the run per lobe, appended by `buildSolids` and dropped with its tile, so
  nothing walks into the stone and nothing stops in the air between two lobes — but only up to
  `FACE_ROCK_SOLID_H` off the low ground, because above that the cut's own wall is what stops him. **AND NO ROCK
  GOES OVER A LADDER'S FOOT OR A FLIGHT'S HEAD** (`climbsNear`) — which is why `Env.replay` adopts the fields,
  materializes the props and only then builds the tiles. `Builder.stamp` copies a prototype in turned, scaled and
  moved, so a forty-metre run costs EIGHT built meshes. **Adding a rock is one seed in `FACE_ROCK_SEEDS`.**
  Everything before this tried to make the sheet itself into rock, and then to scale a whole cliff prop down to
  the drop; the first read as plates pasted on a wall, the second as one boulder per stamp.
- **THE SHEET'S SHADING BUMP IS 0.10 m** (`FACE_BUMP`); at 0.45 the relief noise tilted its normals past 45°.
- **A CUT EDGE SHARED WITH ANOTHER CUTTING CELL GETS NO SKIRT** (`nbCut`) — `edgeOther` reads a neighbour as the
  line through the two corners they share, which across a cut is a ramp, and the skirt stood a fin HALF THE DROP
  tall at every cell of every straight face. A stair neighbour still takes the skirt (its tread is the surface),
  and so does a painted cell under `cliffMinDrop`, which really is a ramp.
- **THE RIM AND THE FOOT ARE AUTO-SCATTER ALONG THE CUT**, never hand-placed — bare rock cap, loose stones and
  grass leaning over the drop above; a scree fillet whose height grows with the drop, and talus below. All on
  `groundAt`, so it follows the neighbour cell's floor. **A FACE STANDING IN WATER IS WET** — `.marble` and a
  darker, cooler tone plus a pale tide line, decided by `paintedDepth` at its foot (so water must be uploaded
  before the tiles). Stair risers take none of the dressing.
- **A STAIR CELL IS ONE TREAD** flat at its own mean snapped to `wf.STAIR_RISE`, and **ITS RISER GOES DOWN TO THE
  LOWEST THE NEIGHBOUR REACHES ON THAT EDGE**, not to the neighbour's CENTRE — a tread is flat at its mean while
  the cell beside it is a bilinear through the two corners they share, so its surface at the edge runs below its
  centre and the riser left a hole under every step of a terrace. A comptime assert keeps the riser at or under
  `STEP_UP`. **A FLIGHT CAN ONLY CLIMB ONE RISER A CELL**, so stairs walk somewhere a ramp cannot only where the
  cell is under `STAIR_RISE / MAX_SLOPE` = 0.60 m.
- **A STAIR THAT CLIMBS MORE THAN ONE RISER A CELL IS A PROP** (`props.stairflight`, `Info.flight`) — sections
  like the ladder's, but each also ADVANCES `flight.run` along local −Z, and the whole run is ONE `WorldDeck` with
  `run > 0` so `floorAt` answers the tread under a point. **THE WALK GATE AND THE BRINK MEASURE FROM WHERE HE
  STANDS** (`stepOk`, `brink` off `from.y` through `standAt`), so the head of a flight meets the shelf at a step
  and not at the drop the LAND takes — and a foe follows him down one.
- **RAMP IS A REGRADE, NOT A CASE** — sweeping it drops the cut and smooths what is left, the only way to open a
  walkable breach through a painted line; a single unflagged cell in a cliff is a 67° ramp and no more walkable
  than the wall it replaced. `Slope` just unpaints.
- `worlds/test_cliff.world` is the bench: a 6 m mesa with a straight face, a ladder and a `stairflight`, a 4 m
  diagonal shelf, a painted stair terrace past `MAX_SLOPE`, and a flooded 3 m pit whose east wall is the wet face.
  `--shot-land` also walks him into the face and prints how far short of the cut the stamped stone stops him.
- **A PLACED `cliff*` IS ONLY THE CLIFFSIDE — THE TERRAIN OWNS THE DROP AND THE TOP** (`world/cliffseat.zig`). Local
  −z is its FRONT. Its seat plane is the deepest front over the face (`proprock.cliffSeatZ`), its lip the LOWEST
  point of the skyline (`Masses.sky`; taller summits crest over), and the bar for "seated" is `HEIGHT_STEP` — the
  finest gap the file can write. The editor's prop box goes GREEN/RED off `seatOf`, the status line prints the
  metres, and Ground > Conform bends the land to the piece: two heights, one exact line, `CLIFF_FACE` on the cells
  it crosses, then the piece walks ≤ half a cell onto the cut the lattice could actually draw. **A seated piece's
  colliders are clipped at the cut** (`env.seatedPart`): nothing behind it, `h` capped at the lip, so the plateau
  stays open, and **`faceStamp` puts no automatic stone where a placed piece already covers the cut**
  (`cliffseat.covers`). **Ground > Plateau DRAGS A RECTANGLE** whose inside goes to one level `Editor.cliffHeight`
  over the ground it started on, with `CLIFF_FACE` round the rim; the rim lands half a cell inside the drag, on the
  lattice's own line. **Raise cliff / Lower cliff are the free-hand pair** (`cliffseat.paint`) — a swept box at the
  brush's own width, one target height pinned for the whole stroke. The height is a free number now
  (3/6/12 m chips, or the stepper's 3..24), NOT a cliff piece's `top`: `cliffseat.rise` measures a piece and only its
  own test reads it, and `Editor.cliffScale` is only the scale a stamped cliff piece takes.
  `worlds/test_cliffseat.world` is the bench, written once by its test if missing.
- **THE SHIPPED MAP'S NORTH-WEST BASIN LIP IS ONE OF THESE** — terraced to two tiers, a **13.25 m** face past
  `FALL_DEATH`. Walking off it kills.

### The fen lurker (`fenlurker.zig`) — the reach is the TONGUE, and the neck never was

**A FIXTURE IN A POOL WHOSE ONLY BLOW ENDED AT 2.35 m IS BEATEN BY STANDING IN THE SHALLOWS.** It cannot walk
(`game.NO_ORDERS` names it), it only answers a body standing IN its water, and it had one move: rise, and bring the
skull down. Everything from the far edge of that skull out to the 9 m it senses him in was free.

- **TWO BANDS AND THEY DO NOT OVERLAP** (`fenlurker.classify`): inside the skull's reach it lashes, outside it spits
  the tongue, and off the tongue's clock at range it does NEITHER — it comes up and **LOOMS**, tracking him at the
  full turn rate. It used to have no band at all and surged at anything inside `AGGRO_R`, so nine metres out it rose,
  swung at nothing and sank. Both bands are taken off the constant the blow itself bills at, never an authored world
  metre, so a body posted at `wf.FOE_SCALE_LO` promises only what it reaches.
- **AND A BEARING THE WIND CANNOT COME ROUND TO IS REFUSED AT THE CHOOSE** (`fenlurker.windSweep`), solved off
  `TURN_RATE` and each wind's own duration rather than picked. The skull answers a CONE so its gate carries
  `LASH_FRONT_DOT`'s half-angle on top; the tongue is a SHAFT and answers nothing but where it points, so thrown at
  a man 170 degrees off it turned the 120 its tell buys and fired 50 degrees past him. What the gate falls through
  to is the LOOM, which turns — a gate with nothing behind it is a hole.
- **THE TONGUE IS FOUR SEGMENTS OF ITS OWN, AND IT RIDES THE SKULL** — not the lower jaw. Hung off `JAW` it inherited
  the 45-degree gape, and MEASURED that put the pad **1.99 m under the water** at 2.84 m out. A tongue leaves along
  the head's axis and the mouth opens AROUND it.
  - **IT TELESCOPES, IT DOES NOT UNCOIL, and that is ONE Z SCALE on the first tongue joint.** `setJoint` translates
    by the rest offset AFTER the local matrix and then through the parent's, so a scale there takes the whole chain
    with it — every segment's length and every offset under it — and the tip travels a STRAIGHT line along the
    skull's axis. A curl was the first attempt: four joints at 142 degrees each still hold 69 degrees of accumulated
    bend at 0.88 of the way out, so the shaft left the mouth, ELBOWED, and dived into the mud short of the man. The
    telescope is also what makes `ext` LINEAR in the tip's distance, which is what `toImpact` solves off. At `ext` 0
    it is inside the skull and `Model.draw` skips it outright.
  - **AND THE TELL IS A LOAD.** It surfaces over the first `GAPE_RISE` of the wind — over the whole of it, the body
    was still half submerged at 0.41 s of 0.95 and drew the same picture as the lash's surge — then rears back on the
    lash's own `swing` channel and snaps forward, RELEASED before the shaft goes: held to the spit, the rear-back's
    own head pitch cancels `GAPE_PITCH` and five metres of tongue leaves level, over his crown.
  - **THE PITCH IS SOLVED, NOT PICKED.** At 16 degrees the shaft crossed the near edge of its own band at 1.74 m —
    three centimetres over a 1.71 m crown, so the one stand the tongue exists to punish was the one it flew over.
    20 (`GAPE_LEAN` 6 at the coil, `GAPE_PITCH` 14 at the skull) puts it at 1.52 m there and 0.77 m at the pad. A
    big LEAN cannot do this job: tipping the coil 30 degrees pitches the head's forward axis with it and drives the
    tip two and a half metres underground.
- **IT IS BILLED SEGMENT BY SEGMENT**, the way the brood's claws are. `foe.weaponReaches` samples five points ALONG
  whatever it is handed, so given the whole shaft as one segment those samples sit 1.24 m apart against a 0.47 m
  grip — it passed clean through a man at 2.95 m and billed nothing. **And a swept bill does not get
  `foe.hurtReach`'s allowance**: that 0.55 m is what a centre-to-centre RADIUS test owes his body, where a sweep is
  already tested against his capsule and may only add his radius and the shaft's own half-thickness (`tongueGrip`,
  which is both the band and the `r` the bill is handed).
- **AND IT HAULS HIM IN** (`TONGUE_PULL`, through `game.noteYank` — the rooted's hook, not a new mechanic). Sized so
  a hit taken at the FAR edge lands him inside the skull's band, which is the rooted's own rule and what makes the
  drag a SETUP rather than a nuisance that moves him and nothing else. The longer reach is the LIGHTER blow and it
  is the one that moves him; the whiff buys the longer punish window, and the reel does not bill — dodging five
  metres of tongue is worth the whole haul-back.
- **ITS ARRIVAL IS SOLVED FOR WHERE HE IS STANDING** (`toImpact`, off `spitShare`). One shaft crossing five metres at
  a constant speed reaches a man at 3 m in a third of the time it reaches one at 4.8, so a fixed share of the stroke
  is right at exactly one range: the parry window would open late up close and early far out. The extension is
  LINEAR on the way out on purpose, which is what lets that be solved rather than searched.
- A flinch swallows the tongue. Left out, the shaft hung in the air through the whole stagger and went on billing off
  a body that had stopped throwing it.
- **AN AUDIO `Id` IS APPEND-ONLY.** `crossingsPerSec` seeds every take off `0x9E3779B9 *% (idx + 1)`, so a row slipped
  in beside `lurker_lash` re-rolled the noise of every voice under it, moved the knight's slam onto the ogre's to
  within 1%, and reddened THE BOSS HAS HIS OWN THROAT in a file the change had nothing to do with. The family is
  named by the NAME (`NAMES` is derived from the enum, `settings.cfg` writes `voice.<name>`), so contiguity buys
  nothing.

### Caves — a second surface UNDER the heightfield (`caves.zig`)

Three grids on their own lattice (`wf.CAVE_N`, **half the terrain's cell** and sharing its points, so cave point
2i IS terrain point i) holding COVERAGE, a FLOOR and a CEILING. No `cave:` row means the map loads and walks
exactly as it did. **ONE UNDERGROUND LEVEL PER POSITION** — two tunnels crossing at different heights are not
representable; that needs a different representation, not another brush.

- **THE CEILING DECIDES WHICH WORLD A BODY IS IN** (`caves.supportAt`, and `env.standAt` routes through it) — feet
  under a chamber's roof are in the chamber, feet at or over it are on the land. Height alone cannot tell a
  hillside from the roof of the cave under it, and neither can a step allowance: solved that way the hero walked
  OVER the hill instead of into the mouth, because the hill was within one step the whole way.
- **NOTHING ELSE IN THE WALK CHANGED** — `stepOk`, `brink`, `gateTerrain` and `groundActor` all ask `standAt`, and
  a cave WALL refuses a step for free because rock answers with the LAND's height, which is a rise no step can
  take. Only the SLIDE needed teaching: `env.blockGrad` reads the coverage gradient underground, so a body slides
  along the rock instead of along the hill over its head.
- **ONE CONTOUR SERVES THE ROCK AND THE AIR** (`caves.cellShapes`) — marching squares on the four coverage corners
  at `CAVE_EDGE`, saddles decided the way `cliffCut` does. The open polygon is floor and ceiling, the chords are
  walls, and the ROCK polygon is what is left of the hill — same crossing points, so a mouth cannot crack against
  the hill it opens through.
- **A MOUTH USES THE ACTUAL ROOF/HILL INTERSECTION** (`CaveCell.roofed`) — terrain and ceiling share its clipped boundary; whole-cell roof removal and vertical mouth bands produce fins. Cliff faces and backing must also subtract cave air.
- **THE CARVE FLOOR IS A FIELD, NOT A NUMBER** (`Brush.dx/dz`) — a stroke stamps a disc many times over, and with
  one floor per stamp the overlaps walked the floor down under themselves and the mouth ended a metre below the
  ground it started on. A slope written per CELL is the same value however many stamps cover it.
- **UNDER ROCK THE SKY IS GONE AND SO IS THE SUN** (`shelterAt`, slots 18/19) — per FRAGMENT, off world position,
  so from inside the mouth the hillside outside is still in daylight while the chamber behind is dark in the same
  frame. The field is coverage TIMES the rock over the ceiling, so it falls to nothing at a mouth on its own;
  ambient keeps 16% under cover and torches are untouched. **BOTH FALLOFFS ARE FULL AT THE SURFACE THEY MEET** —
  keyed to the coverage contour or the ceiling they ring every chamber in daylight, because the wall's own face
  stands exactly on that contour.
- **A SHEET SEEN FROM BEHIND IS ITS OWN UNDERSIDE** — the fragment shader flips the normal on back faces and
  `game` draws the ground two-sided while the eye is under the surface. Without it a chamber looks up through the
  hill at the sky.
- **THE BOOM IS PINNED BOTH WAYS** (`camera.followRoofed`) — it already shortened against rock, and it now stops
  at the ceiling too. **THE NEAR PLANE IS 0.55 m**, so a shot that PLACES a camera underground rather than
  solving one clips through the floor.
- **ROCK IS OPAQUE** (`env.rockBetween`) — nothing on the hill sees or shoots a body in the chamber under it. A
  jump stops at the ceiling (`hero.capUnderRoof`), and the air in a chamber is DRY even under a painted pool.
- **A PLACEMENT CARRIES ITS OWN SURFACE** — `under=1` on a `foe:` row or an `at:` op (one byte, fitting in `Op`'s
  existing padding). `caves.homeY` gives the land back if the chamber it named has since been filled, rather than
  dropping the body through the world.
- **A CARVE WITH THE FLOOR PLANE LEFT UP AT THE HILLTOP LAYS THE CHAMBER IN THE AIR** — a crater, not a cave.
  `--fix-caves <map>` drops every point under `CAVE_ROOF_MIN` of rock, keeps the largest chamber a body can walk
  end to end (four-connected, neighbours within `STEP_UP`), cuts ONE entrance to the nearest open ground on the
  Entrance tool's own grade, and walks it before it writes — dry run unless `--write`.
- **THE CUTAWAY IS SET WITH THE WORLD IT IS OF** (`Env.setCutaway`, never the bare flag) — `env.bodyDrawn` is the
  ONE gate every body answers, so a foe, a folk or a chest standing on the land over an excavated cell is left out
  with its shadow the way `Env.floats` left out a prop. A tile's cliff plates get a second model with the ones over
  a chamber dropped (`cutFaces`/`cutFaceCut`); a tile whose every plate is over one draws none.
- **CAVE LIGHTING INCLUDES THE WALL RELIEF** — the GPU roof texture uses canonical ghost heights and lattice-centred UVs; shelter extends one cave cell into rock, or recessed walls leak triangular patches of sunlight.
- **CAVE ROOFS ARE SEPARATE MESHES** — Inside hides ceilings as well as overlying terrain; floor and wall meshes stay visible.
- **WATERFALL IS A CLIFF STYLE, NOT A DIFFERENT CUT** (`CLIFF_FALL`, `wf.cliffFace`) — persistence and ground sampling retain the cliff topology; its transparent curtain draws after opaque bodies, never blocks a cave mouth or casts an opaque shadow.
- **THE EDITOR WORKS ON ONE LEVEL AT A TIME** (`Editor.under`, the bar's Surface/Underground button, `U`) —
  Underground takes the hill off every chamber (`Env.cutaway`), the cursor lands on the chamber floor through the
  hole (`caves.pickUnder`: the land where it still stands, the floor where it does not, rock met from inside a
  chamber is a wall), what is placed there is marked `under`, gizmos project onto the body's OWN level, picking
  and hover answer only what the level shows (`onLevel`), and a surface prop standing over an open cell is not
  drawn (`Prop.under`, `Env.floats`). The Caves layer turns the level on and nothing turns it off but him.
- **A TERRAIN GESTURE KEEPS ITS INITIAL HIT PLANE** — caves and cliff paint pin the plane through the first visible hit until release; tracing freshly edited terrain moves the brush away from the mouse.
- **UNDERGROUND, GROUND SHAPES THE CHAMBER FLOOR** — Raise/Lower/Smooth/Flat and the roof pair only; Carve preserves an existing floor and can expand the roof. An empty coverage corner must extrapolate neighbouring heights, never interpolate toward the datum.
- **UNDERGROUND, THE GROUND LAYER ALSO WORKS THE CEILING** (`caves.sculptRoof`, Roof up / Roof down) — headroom
  was set at carve time and only a re-carve could change it. The roof never comes down inside `HEAD_MIN` of its
  own floor and never goes up inside `ROOF_MIN` of the hill, so neither stroke can shut a passage or open a
  crater; a roof the hill has already thinned past that is left where it is rather than dragged down by the cap.
- **A CARVE IS NOT A CAVE UNTIL SOMETHING CAN GET INTO IT** (`caves.reachOut`, `Editor.surveyCaves`) — the
  `--fix-caves` walk, flooded from EVERY mouth at once and asked at REBUILD, not per frame (930 us over 638,401
  points). The panel says walkable / SEALED, and `Reach.stranded` counts chambers that are open and unreachable.
- **THE PREVIEW WEARS THE PANEL'S VERDICT** (`carveTint`, depth test OFF) — teal roofed, amber too thin, red open
  to the sky, on the floor and roof rings AND on the words, because the point is the box under a hill that is
  still standing in front of it. An Entrance drag draws its own grade, rings where the hill opens, and goes red
  across any stretch meeting a chamber more than `STEP_UP` over its floor: the failure is fixed by starting FURTHER OUT.
- **A CARVE SOLVES ITS FLOOR ONCE AT THE CLICK** — continue an existing chamber's floor, otherwise fit under the hill if necessary; the floor stays pinned for the complete swept stroke.
- **THE LEVEL AT THE DESTINATION DECIDES `under`, NEVER THE SOURCE'S FLAG** — paste, duplicate and move all
  re-derive it through `underAt`. Carried over, a surface prop duplicated across a chamber lands on the hill and
  `Env.floats` does not draw it. The right-click menu flips one in place, and refuses Underground where nothing is hollow.
- **A PLACEMENT WHOSE CHAMBER WAS FILLED IN IS DRAWN IN THE REMOVAL COLOUR** — `caves.homeY` stands it back on the
  land without a word, so the only way it ever showed was by playing the map and finding it on a hillside.
- **`foe.bulkOf` IS THE ROOM A POSTED BODY TAKES**, measured off its own rig at the pose it is POSTED in — pinned
  in `game.zig` by spawning one of every kind through the real group reset over six seeds. Re-scale a rig and that
  test reds; nothing else would. The editor refuses an underground post through `caves.roomAt` and says both numbers.
- **THE EYE RIDES THE LEVEL'S FLOOR** (`applyCam` reads `levelHeight`) so you can orbit inside a carve; `I` /
  Look inside puts it on the chamber floor at head height looking DOWN THE PASSAGE — across the coverage
  gradient, because the air thins toward the walls and never along the way out.
- **Authoring one**: Caves layer, set HEADROOM, press Fit (`caves.fitFloor`: the floor that leaves `ROOF_MIN` of
  rock under the ground at the cursor) or Sample a chamber, Carve, drag Entrance in from open ground, Fill puts
  rock back. The panel says what a carve HERE keeps overhead before it is made. Then Props/Units on the same
  level to furnish, Ground to shape the floor and its roof, F5 to stand on it (a post at the camera target says
  where). Bench: `worlds/test_caves.world`, authored by `caves.bench`.

### Arenas, fog gates and the spar

- **AN ARENA IS A ROOM AND THE FOG GATE IS ONLY ITS DOOR** (`wf.Arena`, the `arena:` row, `game.holdInRoom`) — the
  ward refuses ONE line 0.8 m thick, which on open ground is a gate you stroll round, and a creature that BLINKS
  never touches the line at all. The row is an XZ polygon plus its own `boss=` seal and holds every body inside
  it, HIS included, for exactly as long as a name on it still stands.
- **IT IS A PUSH-OUT, NOT THE WARD'S REFUSAL, AND IT IS ASKED ON THE STEP'S START** — there is no segment to
  refuse on a blink, and `Arena.hold` pushes an OUTSIDE point IN, so asked about where a body ENDED UP it would
  reach out and drag a creature walking past into the fight.
- **THE SEAL IS THE ROOM'S AND THE DOOR HAS ITS OWN COPY**, PINNED by a test over every shipped map rather than
  trusted to agree: a wall that outlives its door locks you into a fight that is over, and a door that outlives
  its wall is a room you walk out of the back of. The editor closes a room by INHERITING the seal off the gate
  standing in the wall you just drew, and says so loudly when there is no gate on it.
- **A HAND-DRAWN OUTLINE CAN CROSS ITSELF** (`Arena.simple`) — a figure-of-eight's even-odd test answers `false`
  in its own middle, so it holds nothing exactly where it looks most like a room. One corner per 30° about a
  single centre, in bearing order, cannot produce one, and a test refuses any shipped map that does.
- **A FOG GATE IS A WALL UNTIL HE ASKS TO PASS IT** — the ONE crossing allowed is `enterGate`'s walk, refused on
  the SEGMENT rather than left to the push-out, because a roll is 3.5 m in one step and the sheet is 0.8 m thick.
  A SPENT gate never answers. It is a wall to every FOE and every LOOK regardless.
- **THE LATCH AND THE DOOR ARE DELIBERATELY APART** — the latch is his own step crossing the sheet; the door is
  only SHUT while a creature the seal names is still standing, so killing them is what lets you back out. **A gate
  may not shut on the man in it** (`wardClear`).
- **THE SEAL IS A LIST, BECAUSE A DUO IS TWO** (`Op.boss`/`nboss`, up to `wf.MAX_SEAL`) — ANY name holds the door,
  `boss=-` is a doorway that never shuts, and one name still writes no tail when it is the default.
- **A CROSSING IS A GRACE, AND THE CLOCK ON IT IS HIS** (`hero.FOG_GRACE_TAIL`, folded into the one `iFramed` the
  roll answers) — untouchable from the sheet to the far side and for as long as he STANDS there; the tail runs
  only once he moves under his own power and is measured off ground SPEED, so it cannot last longer on a slower
  machine. **`updateGateWalk` RE-HOLDS IT EVERY FRAME** rather than arming it at the door, since the walk moves
  him and a grace armed at the door would arrive nearly spent.
- **AND A NAMED GATE OWNS ITS BOSS'S BAR** (`game.gateEntered`) — where a ward's seal names the creature the bar
  waits until his own step has crossed that sheet; where nothing names it, the aggro ring it always had. **The
  arena is the MAP's to say, authored per gate in the editor, never a list in `game.zig`.**
- **F6 PUTS HIM IN A WALLED ROOM WITH ONE CREATURE AND NOTHING ELSE** (`spar.zig`) — the kind SELECTED, or the one
  the Units brush is holding. **HIS MAP IS SET ASIDE, NOT RELOADED** (one more `Map` at file scope beside the undo
  ring): map, path and dirty flag come back exactly as they were, and camera, layer and brush never move — which
  is why `endSpar`'s BOOL is read, since `Editor.enter` re-solves the camera onto the hero and after a fight that
  is the middle of the room. Coming back takes `Editor.reopen`, everything `enter` puts back EXCEPT the view.
- **THE ROOM IS WRITTEN, NOT BRUSHED** — 42 m of exactly flat floor inside a 7 m wall on a 96 m map whose lattice
  is 0.48 m. The sculpt brush feathers across its whole radius, so a flatten wide enough to level the floor levels
  the wall with it; the field is filled point by point, and ONE cell of the rise already clears `STEP_UP`, which
  is what makes it a painted CUT and not a ramp. **A GATE STANDS ON ITS WALL**, sealing on that one kind, because
  that is what makes it a room and not a clearing — the same contract every boss room keeps, and the repo's own
  test over `worlds/` enforces it. The CAMPFIRE behind him is the RETRY.
- **AND A FIGHT IS NOT A RUN, so it may not write his slot** (`game.saveNow` refuses while `sparring()`) — it would
  have written his position in a 96 m test room, a fresh picture over `save1.png`, and a rail bit for the boss he
  just killed, and `snapRail` only ever GAINS a bit. **THE ROOM HANDS HIM EVERY ARMAMENT AND EVERY SCROLL**
  (`game.sparKit`) — the creature is the test, not the kit — **AND THE FIGHT'S KIT DIES WITH THE FIGHT**: bag,
  sockets and rack are taken where the MAP is and handed back at the one door out (`game.leaveSpar`), or the
  whole item list walks into his run and into his file at the next fire.

### Illusory walls, decks and ladders

**`props.illusory` IS `cliff2`'S OWN MESH WASHED TOWARD SLATE** — it stands in a line of real faces and reads as
one at a glance, and as the odd one to someone who looks. SOLID and BLOCKS SIGHT like any cliff until touched, and
the map places it like any prop.

- **THREE THINGS BRING IT DOWN, ALL THE HERO'S** — a blade that reaches the stone (the blade's own radius inflating
  the face), a ROLL pressed against it, or an arrow planted in it. **A foe cannot dispel one.**
- **IT STOPS BEING A WALL THE FRAME IT IS STRUCK**, and only LOOKS like one for `ILLUSION_FADE` (0.7 s):
  `eachSolid` drops every solid whose `illusionLife` is under 1, so look, step, arrow and roll all pass at once
  while the face thins in place (`Prop.dissolve`, alpha only — never `shrink`, which would sink it).
- **THE BOOKKEEPING IS THE FOG GATE'S** — a slot PLUS ONE on both `Prop.illusion` and `Solid.illusion`. Walls come
  back with the map (`restoreIllusions` beside every `openWards`) and NOT at a bonfire.

**A DECK IS THE FIRST WALKABLE SURFACE THAT IS NOT THE LAND** (`Info.decks`, `env.deckAt`/`standAt`) —
`game.groundActor` asks `standAt`, so `pos.y` is the deck where there is one and `groundAt` stays the question
about the LAND.

- **A DECK HE IS NOT ALREADY UP AT IS NO FLOOR AT ALL** — the gate is the walk's own `STEP_UP`, which is what stops
  a body on the ground being snapped onto a platform five metres over its head.
- **A `hole` CANCELS THE DECK AT ITS OWN `y` AND NO OTHER** (`env.holedAt`) — a trapdoor, and the ONE way a deck is
  not simply convex. Mesh and deck are solved off the same constants (`WATCH_STOREYS` → `WATCH_DECKS`) or it is a
  floor you fall through.
- **WALKING OFF A DECK EDGE IS A FALL, NOT A SNAP** (`game.heroFooting`, `hero.startFall`) — `groundActor` PLANTS
  past `GROUND_SNAP`, which off a five-metre floor is a teleport with a footstep on the end of it. Only a deck does
  this; the land keeps the snap it has always had.
- **THE LENS FOLLOWS HIS FEET, NOT `pos.y`** (`game.syncLensLift`) — both jump (a plant, a mount, a top-out) while
  `pos.y + lift` is continuous through all of it. A climb and a fall off a deck take the FULL lift; a jump takes
  `camera.LIFT_SHARE`.
- **A SOLID CAN HAVE A FOOT** (`Part.y0`, `Solid.y0`) — a LINTEL: open to a body on the floor, wall to one up on a
  deck. **FOUR consumers and they must all know**: `blocksPoint`, `blocksSight`, `env.resolveActorPast`, and
  **`buildSolids`, which has to carry `y0` into the collider the way it already carried `h`** — left behind, the
  watchtower's doorway came out sealed from the ground up.
- **A COLLIDER IS THE SHAPE OF WHAT IT STANDS FOR, AND `props.partsOf` IS THE ONE PLACE TO ASK** — nothing that
  builds, draws or counts a collider reads `Info.parts` itself. **A CLIFF'S ARE FITTED OFF ITS OWN ROCK**
  (`proprock.Masses`, recorded as the mesh is built; `fitParts`): one capsule per lobe and per boulder big enough
  to stop a body, through the section between his feet and his crown. The hand pair it replaced was 2.9 m deep
  against lobes 2–3.4 m deep, so a body stood inside the stone and stopped in the air beside it.
- **MEASURE IT**: `--shot-props` prints a `COLLIDER` line per kind — stone past the collider (a walk-through),
  collider past the stone (an invisible wall), flagged `LOOK` over 0.5 / 0.6 m — off the model's own vertices,
  plus the kind's FOOTPRINT MAP through the walk band, **which is what every part in `INFO` was sized off: author
  a collider from the map, never from the number that looked right.** Stone under `STEP_UP` owes no collider.
  **SIX KINDS ARE LOOSE ON PURPOSE AND STAY FLAGGED** — conifer and willow (the collider is the bole), ash dune
  and sand dune (walked OVER, the collider the crest, since a dune's plan is a lens and no box holds one), fog
  gate (the ward is the wall), awning (cloth over two posts). **Everything else under `LOOK` is a defect.**
  **`solidMat` DOES NOT COUNT `Mat.plant`**, so an agave's collider is its heart, not its blades.
- **PLANT THE ROUND SILHOUETTE, MEASURE THE SQUARE ONE**, and **A COLLIDER MAY HAVE SQUARE ENDS** (`Part.flat`,
  `collision.box`): the solid is the capsule's bounding rectangle in the segment's frame, so a wall, block, plinth
  or house has corners, and a degenerate segment with `flat` is a SQUARE of side `2r`. Round ends left a 7.7 m
  keep's corners 2 m in the open. Rings and posts stay round — a polygon of round-ended segments joins without
  gaps. **Choosing wrong is most of the audit's `LOOK` lines.**

**A LADDER IS THE ONE PROP YOU GET ON** (`Info.climb`, `game.Climb`). Its local **+Z is the open side** he mounts
from and stands off; local −Z is the wall it leans on.

- **IT IS THE FIRST KIND THAT STACKS** (`Info.stack`, `Prop.rise`, `env.drawStack`) — one mesh drawn as whole
  sections up its own axis, because a uniform `scale` drags the rungs apart with the rails. Every other section is
  turned 180°, or the mesh's own wabi-sabi bands the run like a barber's pole.
- **THE SECTION IS THE AUTHORING GRANULARITY, AND THAT IS WHY IT IS 0.90 m** (three rungs) — a run can only be a
  whole number of them, and at 2.40 the band `ladderExit` accepts was narrower than the pitch, so against a cliff
  quantised to `HEIGHT_STEP` most lips had no run that served them.
- **THE HEAD MAY STAND PROUD AND MAY ONLY JUST FALL SHORT** (`LADDER_PROUD` up, `STEP_UP` down) — rails over a
  floor are what you haul on; a head under the lip is a pull-up.
- **THE EXIT ASKS THE WALL SIDE FIRST AND MAY NOT BE A LEDGE** — over a cliff you top out over the lip, inside a
  shaft the stone refuses that side and he steps off inboard. **ON A ROOF THERE IS NO WALL LEFT TO REFUSE IT**, so
  one more stride the same way has to hold him too, which is what keeps him off the merlons.
- **HEIGHT IS A `lift`, NOT A `pos.y`** — the jump's own machinery, so `footPos` and the shadow follow for free and
  a knock-off is `hero.launchFrom`. `game.updateClimb` owns his XZ outright, and the phase is driven by DISTANCE
  climbed.
- **TOPPING OUT IS A HAUL, AND IT IS STILL THE LADDER** (`game.Mantle`) — he lets go `MANTLE_RISE` under the lip
  rather than riding the top rungs, and the beat stands him a full `LADDER_EXIT` in from the edge. **EVERY GATE
  THAT LEAVES A BODY ON A LADDER ALONE ASKS `hero.onLadder`, NOT `climbing`** — footing, terrain gate, push-out,
  lens lift, and the INTERACT button, which is not one of the things `committed()` refuses and reached a bonfire
  in the yard through the haul.
- Forward climbs, back climbs down, back + sprint SLIDES; jump or roll lets go, everything else is refused by
  `committed()`. **NOTHING BUT THE HERO CLIMBS**, so a ladder is an escape from whatever cannot follow.
- `worlds/test_ladder.world` — two shelves, the watchtower's four flights, and the three runs that must REFUSE to
  top out. The test prints every head and exit in metres.

### The day (`daynight.zig`)

One number — `Game.day.hour` — and every colour and shadow in the world is a function of it.

- **ONE DIRECTION CASTS AND THE SHADER KEYS OFF IT** — `keyDir` is the SUN while it is up and the MOON once it
  is down, `gfx.Scene.setHour` its only writer, moving `gfx.sun` and `gfx.sunReach` together. Sun rises at 6 on
  bearing 100 and sets at 20 on 262; the moon is the ANTI-SUN, so the world is never unlit.
- **THE SKY DRAWS THE TRUE PATH, THE SHADOWS DO NOT** — `keyDir` FLOORS the casting altitude at `KEY_ALT_MIN`
  (15°) while `sunDir`/`moonDir` keep the honest angle for the disc. A 2° sun throws a 300 m shadow the 108 m
  ortho box cannot hold. **The one place the two are allowed to disagree.**
- **THE SWAP GOES OVER THE TOP, IN THE DARK** (`keyDir`, `keyDim`) — the moon is the anti-sun, so the key changes
  bearing by 180 at dusk and dawn. Turned round the compass at the floor it wheeled every shadow half a circle
  in 45 real seconds. It climbs from the floored sun through the zenith onto the floored moon in the sun's own
  vertical plane, linear in the shadow's LENGTH, with `keyDim` taking the key to black at the crossing — fade,
  flip, fade back. A test measures a pole's shadow.
- **THE TEXEL SNAP IS TAKEN IN THE LIGHT'S OWN BASIS** (`gfx.lightBasis`) — a world-axis snap stops snapping
  under a sweeping sun and the shadow edges crawl.
- **`Palette` IS THE WHOLE LOOK OF AN HOUR**, keyframed at nine hours and blended with the ease taken off both
  ends. **Retuning means moving a ROW, not a shader.**
- **ITS TWO HALVES ARE ON DIFFERENT SCALES** — `key`/`ambGround`/`ambSky`/`haze`/`hazeBank` are read by the
  SCENE shader, which gammas its output: PRE-GAMMA and near-black. Every `sky*`/`cloud*` value is read by the
  SKY shader, which gammas nothing: LITERAL SCREEN VALUES. **At the dark hours `haze` must sit UNDER what the
  ground is lit to**, or the distance is brighter than the foreground.
- **THE ANCHOR IS NOT A KEYFRAME.** `SHOT_HOUR` reproduces `gfx.SUN_DIR` — the light this game was authored,
  measured and photographed under, and the bearing `shots.LIT_YAW` is framed off. `SUN_ALT_MAX` and `SHOT_HOUR`
  are SOLVED from it; move `AZ_RISE`/`AZ_SET` and you solve them again. `--shot` pins and FREEZES that hour.
- **The controls.** Menu > Debug > `Hour`; in the EDITOR `,` and `.` sweep it and Shift runs (the clock is held
  there, so those are the only writers), and the same hour is on the World card as a readout, a quarter-hour
  stepper and four marks worth authoring at, `Anchor` among them. A BONFIRE offers `Rest until morning` /
  `Rest until evening`, always FORWARD (`hoursUntil`). **EVENING IS AFTER DARK** — morning 8:30, evening
  `EVENING_HOUR` (an hour past `SUNSET`, sun DOWN and moon casting), deliberately NOT `SHOT_HOUR`; a comptime
  assert pins it past the horizon.
- **THE FIRE TOUCHES THE CLOCK NOWHERE ELSE** — the hour you walk in at is the hour you sit in, and the two
  `Rest until…` rows are the only thing at a fire that moves the light. Nothing is restocked there: `hero.sit`
  made him whole when he sat down.
- Verify with the strip: `shots/140`–`147` are eight hours of ONE view shot into the light's own quarter.
  **The arc is the test** — a frame that reads like its neighbour is an hour the palette is not earning.

### What the hour does to a creature

- **A BODY READS `daynight.dayShare`, NEVER `dayAmt`.** `dayAmt` is the SUN'S HEIGHT and eases over the whole
  span, so it cannot tell a creature whether it is day. `dayShare` is a ramp across `WINDOW_FADE` (0.75 h) either
  side of each horizon, exactly 0.5 AT the horizon, and every gate in the game is `< 0.5` / `>= 0.5`.
- **WHEN A PLACED BODY IS OUT IS AUTHORED, AND DERIVED UNTIL IT IS** (`wf.FoeWhen`, `wf.foeWhen`) — a row with
  no `when=` means *the kind's own answer*, so a default can be retuned in one exhaustive switch without
  touching a map on disk. **A STATUE AND A ROOST ARE NOT ABSENCES** — those bodies are present and inert.
- **AND ABSENCE REACHES EVERYTHING THROUGH ONE FIELD** (`foe.Win` on the `Leash`, stamped by `game.markHour`).
  `in` is a SHARE and it is the alpha `foe.drawGroup` hands the shader, so a body comes and goes across the
  horizon instead of popping. Under `foe.WIN_SOLID` it is not there at all: `drawGroup` skips it, `foe.reached`
  refuses every blade, `game.disguised`/`phased` take it out of lock-on, AoE and collision, and
  `foe.sensedDist` bends its sense of the hero past its own ring — which holds every state machine at home
  without a second decision tree in any of them.
- **A CREATURE WHOSE BEHAVIOUR TURNS ON THE CLOCK OWES A `foe.Sky`** and reads `sky.night`. **A BLOW OUTRANKS
  THE HOUR, and ORDERS outrank it outright**: a fight carried into the dawn finishes, and a route the map
  authored is the author saying this one is about.
- **FLAME IS A FACT ABOUT THE WORLD, NOT A READ OF WHAT HE IS HOLDING** (`foe.Glare`, `game.markGlare`) — `k` is
  the share of the flame's radius the body stands inside, `shy` the latch (`SHY_ON` 0.55 / `SHY_OFF` 0.42).
  **ONLY THE FLAME HE CARRIES**: letting a map-placed brazier hold a camp off would silently retune every
  encounter standing near one. The skitterer and both spiders back out of it, **and one blow undoes that**,
  which is what stops a torch being an off switch.

### The weather (`weather.zig`)

**IT IS AN EVENT, NOT A SETTING.** A storm arrives every `DRY_LO`..`DRY_HI` and runs `WET_LO`..`WET_HI`, ramping
9 s in and 14 s out — measured over an hour: **9 storms, raining 26% of the time, dry gaps 162–405 s**. The clock
is PURE (seconds and 0..1), so a test runs a day without a window. Weather does not run in the EDITOR and
`--shot` forces one (`shots/150`–`155`).

- **TWO STRENGTHS, AND ONLY THE HEAVIER HAS A SKY**; the moderate storm is the minority. Lightning waits for the
  storm to arrive (`FLASH_AT`).
- **A STORM BREATHES WHILE IT IS THERE** — `gustAt` is two slow swells on periods that do not divide (17.5 s and
  30), riding the TOP down (not the level, so the ramp still owns how fast the sheet may move).
- **THE STRIKE IS A DOUBLE AND THE THUNDER IS LATE** — a spike, a dark beat, a lower second flicker; the sound is
  behind the light by the strike's own distance (1.7–7.5 s) and arrives even if the rain has stopped.
- **THE PICTURE IS ONE MESH** (`Rain`) — a cell of `STREAKS` one `CELL_H` tall, drawn STACKED up the camera's
  column and slid by a phase that WRAPS on the cell; the heavier storm draws the same cell again, offset.
  **7,200 triangles, 4 draw calls gentle and 7 moderate**, test-pinned. Rain as PARTICLES would be thousands of
  live motes at one immediate-mode sphere each.
  - **WHAT COSTS IS FILL, AND FILL IS DENSITY** — streaks per square metre, which a test prints: **0.55/m² out
    to 24 m**. Spreading the disc IS the thinning, since streaks are laid by area.
  - **THE COLUMN STANDS ON THE MAN, NOT ON THE LENS, AND ITS RIM FADES.** Centred on the camera the disc reached
    24 m behind the lens and 19 ahead of the hero — the short side being the side the frame looks at; and it must
    be a point the camera does not ROTATE, since a lead off the camera's forward slides the sheet sideways at
    40 m/s when you turn. The rim thins past `TAPER_FROM`, **baked into the geometry** because a per-streak
    opacity is the one thing this renderer has no channel for.
  - **A STREAK IS TWO CROSSED CARDS** — a single card is invisible edge-on; two segments each, so the tail fades
    in the GEOMETRY. **AND THE SHEET DRAWS WITH BACKFACE CULLING OFF**: a card is ONE winding, so under raylib's
    default cull a lens in the streaks' −X/+Z quadrant saw NEITHER face and the rain stood on one heading and
    vanished on the turn.
  - **THE SLANT IS WORLD-FIXED** (0.30 across the fall) so turning the camera turns the rain. `FALL_MPS` is just
    over real rain's 7–9; at 21 a streak crossed twenty-three times its own body in a second, which is a smear.
  - Draws LAST through `Scene.beginFade`: no depth written, still depth TESTED, which is what puts it behind the
    wall you are standing under.
- **THE STORM IS A LAYER ON THE PALETTE, NOT A RECTANGLE** (`daynight.overcast`). Cloud does four things a
  rectangle cannot: puts the KEY out (`STORM_KEY`, so shadows and every specular go with it), leaves the AMBIENT
  alone (an overcast sky is one enormous soft source), takes the WARMTH out (`slate` is luma-preserving — a hue
  change, not a dimmer), and CLOSES THE DISTANCE (`gfx.HAZE_STORM` 3.1× density). **Every term is a factor on
  the HOUR'S own value, never a constant.** The fog distance has a DEBUG override answering TWO questions:
  `fogK` is the haze DISTANCE, `fogAmt` how foggy it IS.
- **SOUP IS DENSITY ALONE** (the `soup=` band on a `location:`, `gfx.HAZE_SOUP_D`) — no palette move and no mist
  banks, so it closes the distance without touching its colour; every band MULTIPLIES, so a storm in the soup
  shuts the world in harder than either. `soup=1` is the debug `Fog: Soup` override, and `menu.fogMulOf` reads
  the same constant so the two cannot drift.
- **THE FOG HAS A SHAPE: THE STRAY BANKS** (`weather.Mist`) — seven banks standing in the field, so fog is
  somewhere you walk through rather than a value. **THE GRADIENT IS IN THE GEOMETRY**: one bank is 22 lumps
  scattered with density falling off outward, so alpha compounds in the middle and thins at the rim (vertex
  alpha is the EMISSIVE channel, and three concentric shells would read as three rings). **THE SLOWEST THING IN
  THE GAME** — 0.045–0.16 m/s, 94 s to cross its own width. Re-seeded out past `MIST_R`, never in view. Three
  mesh variants (the repeated-big-prop law).
- **EMBERS RISE, THEY DO NOT FALL** (`weather.Ember`, the `ember=` band on a `location:`) — the spore field's
  construction with the phase ADDED to the base so the stack climbs, at 0.85 m/s (15× slower than the rain, 10×
  faster than a spore). **THE FIELD FLICKERS BUT NEVER BLINKS**: a shoal winks on `EMBER_WINK_SECS` (6.5 s),
  squared so it is lit briefly and dark longer the way sparks are, held off zero, and a test pins the sum's
  swing under 12%. Motes are 1.2–3 cm and EMISSIVE — under the stroke's 7 cm, or a field of them reads as smoke.
  - **THE SMOKE IS THE MIST, TINTED** (`bankTint` toward `SMOKE_BANK`, a warm dark grey — smoke TAKES light,
    fog scatters it). **AND THE SKY IS A LAYER ON THE HOUR** (`daynight.smolder`, on top of `bloom` as `bloom`
    is on `overcast`): haze darker and warmer, horizon thrown to orange, key warmed a little, stars mostly gone.
    Every term a factor on the hour's own value, so a smoking field at 3 a.m. is a darker night with an orange
    horizon and not a lit one — tested at noon and at 3.
- **THE DRY SKY HAS BIRDS IN IT** (`weather.Skein`) — **AN EVENT, NOT A FLOCK THAT LIVES THERE**, the storm's own
  law: one flight arrives, crosses, and is gone. Measured over an hour: **63 crossings, 4 to 17 birds, in the sky
  28% of the time**, gap **18–62 s**, and the clock runs ONLY on a dry sky (plus `SKEIN_AFTER_RAIN`) so a long
  storm cannot bank up a flight. A flight already in the air finishes its crossing. **THE COUNT IS DERIVED IN
  THE TEST, NOT PINNED BESIDE IT** — a mean gap plus a crossing predicts 65 against 63 flown.
  - **THE SKY IS SMALLER THAN IT LOOKS, AND ANYTHING PUT IN IT IS SOLVED AGAINST `camera.skyTop()`** — half the
    lens less the resting pitch, **11.46° above the horizon**, and that is the whole of the sky a player sees
    without holding the stick up. Authored at 30–62 m up the lowest elevation any bird reached over a whole
    flight was 15.1° and the middle of a crossing was 48°: sixty-two flights an hour and not one on screen.
    **THE HARNESS DID NOT CATCH IT BECAUSE BOTH BIRD SHOTS HELD THE LENS UP AT THE FLOCK** —
    `157b_birds_resting.png` is the frame a player actually gets, and a test walks half an hour of sky and pins
    every bird inside it (3.5–8.3° now).
  - **THE WHOLE BAND IS DERIVED, NOT PICKED** (`SKY_SHARE`, `skeinNear`/`skeinWide`/`skeinRim`) — ceiling 0.70 of
    `skyTop`, closest approach `HIGH_HI / tan(ceiling)` so the highest bird at the nearest point sits exactly on
    it; `HIGH_LO` is the floor because a cliff stands 15.5 m and they used to fly through them. **THE OFFSET
    NEVER PASSES THROUGH ZERO** — a line over your head is a line whose middle is at 90°, and the middle is the
    part you were meant to see.
  - **AND THE HAZE IS TURNED DOWN FOR THEM ALONE** (`gfx.Scene.setHaze`, `SKEIN_HAZE`, paired like `beginFade`).
    A bird is not a surface the distance veils, it is a SILHOUETTE, and haze does not soften a silhouette — it
    deletes it by pulling it to the sky's colour. At 0.013/m the world leaves 4% of a thing at 240 m, which is
    where the band has to be; at 0.35 of it, 33%. **THE FADE IS METRES, NOT A SHARE OF THE CROSSING**
    (`SKEIN_FADE_M`) — as a fraction the ramp got steeper every time the chord came in shorter.
  - **A BIRD IS A SILHOUETTE**, so it is opaque and nearly black; at vertex alpha 210 they came up self-lit and
    pale and washed into the very haze they are read against (the 248+ law). **THE FLAP IS A SQUASH OF THE V, NOT
    A BONE** — at this range a wing is a couple of pixels and what reads is the silhouette breathing; cheap
    enough that every bird carries its own period, and a test pins that no two in a skein share a wingbeat.
  - **DIFFERENT ANGLES IS A RESULTANT, NOT A DIE** — bearings summed as unit vectors pull 0.38 one way over an
    hour where 1.00 would be a flight path. "No two in a row within N degrees" is a dice roll that fails on an
    honest sky about a third of the time.
  - **AND THERE IS A DEBUG ROW** (`menu.DBG_BIRDS`) — an event on a clock measured in minutes is not a question
    anybody can sit and answer. It sends one ACROSS his view, and the request survives the menu being open
    (`takeBirds` drains on the first frame after it shuts, which is the frame he is looking at the sky again).
- **THE BED IS THE STORM'S, NOT THE HOUR'S** (`audio.setRain`) — three bands with a granular patter (a hiss
  alone is tape noise, a low roar alone is a motorway). Thunder is a ROLL with no transient at its head, and it
  is the third kind of ambient voice (`AMBIENT_EVENTS`): not a bed, not a call, fired by the world.

### The Sun Palace (`proppalace.zig`, `propdesert.zig`)

Gold, emerald and sandstone in a desert — the Gilded Ruins' architecture at three times the scale, and the only
biome whose FLOOR is authored (`wf.Soil.sand`). Bench: `worlds/test_palace.world`.

- **ONE MUQARNAS, ONE BAND, ONE RING, ONE STAR** (`propart.muqarnasInto`/`giltBandInto`/`giltRingInto`/
  `starInto`), each taking an `art.Tone`. What separates the two families is that row and three motifs the
  palace adds — the stepped fret (`grecaInto`), the sun sign (`ziaInto`) and the pecked panel
  (`glyphBandInto`). `art.Course.tone` is the same idea for coursed stone: `null` is the grey every ruin is
  built of.
- **THE FRET IS ONE LINE THAT NEVER CROSSES ITSELF** — two continuous rails with a meander between them, one
  repeat per band height. Broken into separate keys it reads as a row of blocks; at a third the pitch the whole
  frieze greys out at twenty metres.
- **THE SIGN IS SIZED OFF THE WALL THAT HOLDS IT**, never off the prop — `sunGateMesh` solves its radius from
  the tympanum's own height, or the rays carry past the cornice.
- **THE JEWEL IS A LIGHT, NOT A COLOUR** — alpha is the emissive channel, so `EMERALD_LT` (150) burns hardest
  and `EMERALD_DK` (238) barely at all. Two kinds carry a real point light off `GEM_LIGHT`.
- **THREE ARE WALKED INTO AND ONE IS WALKED UP** — hall and vault colliders are SHELLS with doorways (the course
  over a door is a `Part.y0` lintel); the terrace carries a deck at 4.00 m reached by `palacestair`, the third
  kind that stacks and the widest flight in the game.
- **THE SAND IS THE ONLY PAINTED GROUND WITH ITS OWN GRAIN** — `shaders.paintedSoil` branches on its ordinal for
  a 58-cell hash at a third the amplitude of `blades`; on the generic term a desert floor comes back as scree.
- **EVERY PLANT HERE IS TALLER THAN IT IS WIDE**, which is what water-starved looks like. A cactus is FLESH, its
  flutes 4% of the radius proud, and one pale areole stands in for twenty spines — the halo is the read, and it
  has to beat the flesh (198 on screen against 118) or the plant is a green post.

### Performance — how a 1000 m world stays cheap (`env.zig`)

- **UNIFORM GRID (CSR)** — props bucketed by 16 m cell into two indexes (structures, flora), built by counting
  sort into one flat array. Each cell carries the MAXIMA its pass needs, so a whole cell can be rejected first.
- **THE LIT PASS culls per cell then per prop** — four frustum side planes plus each kind's `view` distance.
- **THE DEPTH PASS culls by SHADOW REACH, not camera distance** — a caster throws its shadow `gfx.sunReach`
  times its height sideways, the cotangent of the sun's elevation solved from the HOUR
  (`daynight.shadowReach`, written only by `Scene.setHour`). A prop matters iff its footprint plus that reach
  can touch the ortho box (`castsInto`).
- **COLLISION + ARROW FLIGHT query the grid**, never the whole solid list.
- **Check it, don't trust it** — Menu > Debug > Stats prints the live counts and `--shot` captures them. If
  `drawn` approaches `props`, a culler has been defeated. Caps are init-time PANICS
  (`MAX_PROPS`/`MAX_SOLIDS`/`MAX_SOLID_REFS`): a silently dropped collider is a walk-through wall.
- **A CULLER BUG LOOKS LIKE AN EMPTY WORLD, AND ONE-ORIENTATION TESTS MISS IT** — `View.fromCamera`
  sign-corrects its plane normals against the camera forward rather than assuming a handedness. Its test sweeps
  seven headings. **`env.View` is THE frustum, there is one of them, and a second culler is the empty-world bug.**
- **THE OCCLUDER FADE** (`env.markOccluders`) — a prop between lens and hero goes thin, keyed to how much of him
  it hides. Three rules keep it from reading as a switch: the geometry sets a TARGET and an EASED ramp walks you
  there (`OCCL_IN`/`OCCL_OUT`, out slower, `easeShape` taking speed off both ends); it stops being in the way
  over a BAND not a plane (`OCCL_DEPTH_BAND`); and `OCCL_MAX` counts what is in flight, both directions. **The
  shape is a pure function of where the value SITS, never of where a travel began.**
- **EVERYTHING THINS EXCEPT WHAT SAYS `solid`** — architecture, cliffs, the water sheet, the bonfire. The flag is
  that way round because as an opt-in every kind added afterwards opted out by silence. **ONE SOLID THINS AND WHAT
  THINS IS ITS VEIL** (`env.veilThins`, off `Info.ward`): the fog gate's arch is masonry and stays put, the sheet
  hung across it is the thing standing between the lens and him, so the STONE keeps the ordinary pass at full
  alpha and the SHEET carries `fade` in `drawVeils`.
- **GROUND COVER THINS FROM HIS WAIST UP** (`OCCL_TALL`, the rig's SPINE at 0.640·H) — `markOccluders` walks BOTH
  indices and the height gate is what keeps grass out of it. **Coverage will not do that job**: a tuft against
  the lens scores 0.54, over three times `OCCL_MIN`. **The gate is the INSTANCE'S height, `top * scale`, not the
  kind** — the scatter stamps 0.72..1.38.
- **COVERAGE OPENS THE GATE, DEPTH SCALES THE ANSWER** (`thinOf`) — `OCCL_MIN` is a coverage figure and nothing
  else. Multiplied together before the threshold, a mass a metre in front of him was discounted under it.
- **THE OCCLUDER VOLUME IS NOT THE COLLIDER** (`props.Blocker`, `Info.occl`) — a collider is sized for what you
  WALK INTO, an occluder for what you SEE THROUGH: a conifer's collider is a 0.58 m pole against boughs that
  block the view at 3.4 m. A kind with no `occl` falls back to the colliders plus `OCCL_SKIRT`, right where the
  two shapes agree — a pillar, and an ARCH, whose opening must stay see-through.
- **A THINNED OCCLUDER DRAWS LAST, AFTER EVERY OPAQUE THING, AND BACK TO FRONT** (`env.drawThinned`) with the
  depth MASK OFF; left in cell order the HERO came afterwards and composited at FULL opacity over it. Drawn
  last, the tree's alpha is what mattes HIM, so the reveal IS the ramp.
- **IT BLENDS ONE LAYER PER PIXEL** — a trunk stacks three or four surfaces along the ray and blended one after
  another the alpha COMPOUNDS. Each prop lays its own depth down first with the colour buffer held (`dst =
  0·src + 1·dst`, rlgl having no colour mask), and the pass after draws under LEQUAL.
- **A THINNED PLANT KEEPS ITS WIND** (`drawThinned`) — `drawFlora` draws inside `Scene.setWind(true)` and this
  path is outside it, and it goes on for BOTH of the pass's draws, never one: the depth prepass has to lay down
  the same geometry the colour pass draws.
- **A FULL LIST GIVES ITS SLOTS TO WHAT HIDES HIM MOST — TAKEN OFF SOMETHING STILL SOLID** (`wantFade`). Nothing
  outside the list is ticked, so dropping an entry that has already left solid strands it thin or snaps it back.
  A tree a frame late is not something the eye can see; a tree jumping back to solid is.

## Triggers, folk and dialog

StarCraft's trigger system on this world: CONDITIONS and ACTIONS; every condition must hold, then the action list
runs in order. `worldfmt.zig` holds the definitions as map data, `trigger.Runtime` everything that changes,
`dialog.Session` the one conversation that may be on screen, `npc.zig` the body you speak to. **Nothing about
any of it is authored in Zig.**

- **THE GENERAL-PURPOSE STATE IS WHAT MAKES IT COMPOSE** — named switches (`flag`), named integer counters,
  countdown timers. Without them every new bit of story state wants a new condition kind.
- **A NAME IS INTERNED TO A SLOT AT LOAD**, so a condition costs two bytes; the map carries the
  `flags:`/`counters:`/`timers:` tables so the file stays self-describing.
- **EVERY OTHER REFERENCE IS RESOLVED AFTER THE WHOLE FILE IS READ** (`link`) — a dialog may be declared below
  the trigger that opens it. An unresolved one is a LOAD ERROR.
- **EVALUATED EVERY FRAME, NOT ON A CYCLE.** A PRESERVED trigger is held off by `REPEAT_GUARD` — without it
  `always` + `preserve` fires sixty times a second and never lets go of the screen.
- **A CONDITION IS LIVE, NEVER STICKY** — `region` is SC1's Bring exactly: true while he stands in it. Two
  conditions that come true at different moments are what the SWITCHES are for. **AN EMPTY `when:` LIST NEVER
  FIRES**; `always` is a condition you write down.
- **A `dialog` ACTION BLOCKS ITS OWN LIST AND NOTHING ELSE** (SC1's Transmission), and so does `wait`. Only one
  conversation may be up, and a trigger that wanted the screen is not advanced that frame — deferred, never
  dropped.
- **`deaths` IS MAINTAINED BY THE ENGINE**, off `justDied` through `eachTarget` — a latch would bill one death
  sixty times. The egg sac has no such edge, so the brood's own `bursts` bills it.
- **THE SCRIPT LAYER IS ARMED WHERE THE MAP CHANGES, NOT WHERE THE HERO DIES** (`game.armScript`).
- **ONE BUTTON, ONE WRITTEN PRIORITY ORDER** — bonfire, then whoever is standing there, then a box
  (`game.interact`). The HUD prompt reads the same order.
- **The dialog panel** is SIZED TO WHAT IT HOLDS, growing upward off a fixed bottom edge. **A GATE HIDES A LINE,
  IT DOES NOT GREY IT** — nothing here has a reason to show, and a greyed row with no reason is worse than a row
  never offered. **YOU MAY NOT WALK OUT MID-SENTENCE**: no cancel, a conversation is left through one of its own
  endings, which is what lets `talked` mean "has heard this". The world's HUD goes away behind it. **A NODE'S
  `act:` FIRES ON ARRIVAL AND A CHOICE'S `gets:` ON THE PICK.**

### The folk (`npc.zig`)

Not foes: no `Vitals`, no `Leash`, no blade. **Do not let the foe contract grow into them by accident.**

- **A MAN STANDING STILL IS THE HARDEST THING TO ANIMATE** — THREE clocks at rates that never line up (breath, a
  weight shift, a head drift) so the loop never shows.
- **THE WEIGHT SHIFT IS A PELVIC LIST, NOT A SLIDE** — translating the pelvis sideways carries both hips and
  `legChain` solves each leg straight down from its own hip, so both feet travel too. A roll about the pelvis
  raises one hip and drops the other. **AND ITS DROP IS PAID BACK AT THE PELVIS**: at rest this rig's leg is
  EXACTLY straight, so a pelvis a millimetre below rest puts the sole through the floor — there is no foot IK.
  Lift by `hx·sin(list)`.
- **NO PITCH AT ALL AT THE ROOT** — a root pitch rotates the LEGS, so one degree of stoop levers a planted foot
  half a centimetre into the ground. A stoop is thoracic anyway.
- **HE TURNS FIRST, THEN WALKS** (`TURN_GATE`) — stepping off before he is pointed at it makes travel disagree
  with facing, which IS a sidestep as far as the shared gait is concerned.
- **THE STAFF IS THE OTHER HALF OF THE GAIT** — a walking staff plants with the OPPOSITE foot, so the staff arm
  drives the pole down once a stride while the free arm swings at full amplitude. **WHERE IT POINTS IS AUTHORED
  IN THE WORLD, NOT IN THE WRIST** (`warrior.swingTilt`'s law) — built down the wrist's own −Y it inherits the
  entire arm chain (46° off plumb at rest); the fit BILLS THE ARM so `STAFF_TILT` means degrees off plumb.
- **THE BOOT IS THE HERO'S FOOTPRINT EXACTLY** — the gait curves plantarflex the ankle to a fixed angle at
  toe-off, so a longer toe is a longer lever below the plane and `legChain` can only level the ankle.
- **THE TWO HEAD VARIANTS ARE WHAT MAKES TWO OF THESE TWO PEOPLE** — hood up, hood back, picked by seed.
  Everything else varies through the POSE, which costs no mesh.
- **VALUE CONTRAST BETWEEN TWO LARGE AREAS CANNOT SURVIVE FULL DAYLIGHT ON THIS SUN** — a sunward face reads
  `255·(albedo·1.72/255)^(1/2.2)`, so albedo 40 comes back at 142 and 58 at 168. Layer on HUE, which the sun does
  not flatten, and spend value contrast only where the area is small or is a hole.
- **MOSSBEARD, the tree smith:** **THE STROKE IS THE IDLE, NOT A `Gesture`** — a gesture has a clock that ends;
  he is doing this when you find him and when you leave. `Wanderer.hammer` is a repeating phase and `struck` is
  the one-frame edge. **THE RISE TAKES FOUR TIMES AS LONG AS THE FALL, AND THE ELBOW CARRIES THE RAISE**
  (comptime-pinned, both: a shoulder that did the lifting reads as an executioner, an even rise/fall reads as a
  woodpecker). **AND IT OVERSHOOTS** — `HAMMER_REBOUND` bounces the head off the anvil and the trunk drives past
  its own stoop with it; there is no hitstop to fake the weight with. **THE BEARD ARRIVES LATE** — read off the
  stroke's phase shifted back by `BEARD_LAG`; a rope that moved WITH the arm is a rope nailed to it, and that
  late arrival is most of what makes the hammer look heavy. **BOWED, NOT FOLDED** — sad is the head, NOBLE is
  that the shoulders stay square under it, and the split is asserted, not described. **THE ANVIL IS SOLVED OFF
  THE STROKE AND NOT THE OTHER WAY ROUND** (a test re-measures the pair every build). **HE STILL HAS TO FIT
  THROUGH A DOOR** — crown pinned under `propart.TOWER_DOOR_HEAD`.
- **THE FORGE YARD IS FOUR PROPS, NOT ONE MESH** (`propforge`) — anvil, forge, quench trough, tool rack, laid
  out by an author. **THE COAL BED IS `Mat.flame`, NEVER `Mat.ember`** — ember is one of the two
  VERTEX-ANIMATED ids and is for sparks that FLY UP. **THE HOOD STANDS CLEAR OF THE FIRE**, a cone, raised,
  leaning back, open at the front. **A BIG SMOOTH PROP NEEDS A DARKER ALBEDO THAN A SMALL ONE OF THE SAME
  MATERIAL** — `art.TIMBER` on a 0.6 m capsule reads at 180 where the same value on a fence rail reads at 130,
  so the family carries its own timber and stone a third under `propart`'s. **AND A 6 mm DISC IS ALWAYS WHITE**:
  hammer scale scattered on the floor had every normal straight up into the key. Ground litter is a `decor` op.

## Sight and leashing

**A LOOK IS A SEGMENT AND IT IS TESTED EXACTLY** (`collision.blocksSight`) — one segment-vs-capsule test per
solid, never a walk of samples, passing OVER anything whose blocking height is under both ends. **THE GRID IS
WALKED, NOT COPIED** (`env.sees`) — `nearSolids` truncates at `MAX_NEAR`, which over a 20 m line through a wood
quietly drops the wall it was asked about. **IT IS ASKED ONCE A FRAME, BY THE GAME** (`game.markSight`) for
every foe inside `game.sightR()` — the widest ring in `FOE_GROUPS` plus a metre — and stamped on that foe's
`Leash`. **Creatures do not ask it themselves** — the prop grid belongs to `env`.

- **WHAT IT LOSES IS ITS EYES, NOT ITS MEMORY** — `Leash.blind()` needs `SIGHT_MEMORY` with no line, longer than
  `LEASH_CALM`, so breaking sight can never shed a foe faster than walking away does. **A blow outranks
  blindness** (`roused()` beats `blind()`).
- **START FAR, STOP NEAR** — turns for home past `foe.leashR(AGGRO_R)`, stops inside `LEASH_HOME_R`. **That gap
  IS the debounce.**
- **THE TETHER IS THE CREATURE'S OWN NOTICE RING PLUS `LEASH_SLACK`**, not one authored number: a flat 30 m was
  also THE SPACING BETWEEN CAMPS, so a tether reached the next encounter.
- **THE PATCH IS A PLACE, NOT A SEPARATION** — both ranges in `Leash.tick` are measured FROM THE POST: how far
  the CREATURE has come, and how far the HERO is. Asked as the gap between the two BODIES, tethers nominally
  17–30 m long measured out at 34 m to 176 m. A test walks the field and pins each one.
- **ONLY AFTER `LEASH_CALM` WITH NO BLOW GIVEN OR TAKEN**, and only once the hero has left the patch. **A WALK
  HOME IS NOT BLIND** — step back into the patch, or land one blow, and it turns on the spot. **RE-ENGAGING
  COSTS `REENGAGE_HOLD`**, in which it cannot try to leave again.
- **A FIGHT IN PROGRESS OUTRANKS THE TETHER, and that is not a leak** — `noteCombat` is stamped by every blow
  either side lands, so a leechfly that rides him for eighty metres has been FEEDING the whole way. What a tether
  owes there is a prompt let-go once the biting stops: a CLOCK, not a distance.
- **ONE PLAYER BLOW ROUSES IT FROM ANY RANGE for `PROVOKE_ROUSE`** — a COUNTDOWN, not a level, because it has to
  outlast the walk. Only a `pierce` blade also snaps its facing back down the shaft. **KEEP AT IT AND THE LEASH
  BREAKS** (`PROVOKE_BREAK`, held `PROVOKE_HOLD`) — the anti-cheese, not gated on `pierce` or the sword is
  exempt.
- **IT REACHES EVERY STATE MACHINE BY BENDING THE SENSED RANGE** (`foe.sensedDist`), not by bolting a second
  decision tree onto each. Only the DECISION sees the bent number — **every decision, including the ones after a
  leap** (the kobold's dash and the archer's backstep both re-decided on the raw distance when they landed).
- **A TELEPORT IS A JUMP, AND THE ROOTS REFUSE IT** (`shade.wantsBlink` → `foe.canLeap`), gated where the move
  is CHOSEN. It is also the one move that must not fire out of a STAGGER: a creature that vanishes mid-flinch
  erases the punish window, so the blow sets a latch (`spooked`) and the blink is spent at the next choose site.

## Saving, and the boot screen (`save.zig`, `menu.zig`)

**YOU SAVE AT BONFIRES AND NOWHERE ELSE.** No Save row anywhere; sitting down IS the save,
`game.tickRest`'s `justEntered` is the one line that writes one, and it lands in whatever slot is being played
without asking. **THREE SLOTS**, `save1.dat`…`save3.dat`, each with a `save<n>.png` beside it.

- **THE FILE IS TEXT IN THE MAP'S OWN GRAMMAR** (`key: value`, `version:` first). Unknown key, bad version or
  another map's name are LOAD ERRORS — **a save is refused whole rather than applied in half.**
- **A SLOT IS WRITTEN BESIDE ITSELF AND RENAMED OVER IT** (`worldfmt.save`'s rule, and this is the other file the
  game writes): `createFile` truncates first, so a render that failed part-way took the save it was replacing.
- **A FILE THAT WILL NOT PARSE IS NOT AN EMPTY SLOT** (`Shelf.unreadable`/`holds`) — read as empty it is offered
  for a new game and overwritten, and nothing ever said it was there. The row says so, and DELETE still takes it.
- **THE FIRE HE SAT AT IS WHERE HE COMES BACK, AND SO IS THE ONE HE LOADED AT** — `justEntered` stamps
  `hero.setSpawn` at the SEAT for the live session, and `save.scatter` takes the checkpoint off `at:`, the
  position IN THE FILE, because every write is inside the rest flow so a save's position IS a bonfire seat and a
  second stored point can only be the stale one. The file's `spawn:` row is READ AND DROPPED and the key may
  never leave the parser: an unknown key is a refused save and every file on disk has that row. `enterMap` still
  stamps the entry, so a new map is its own checkpoint until he next sits down.
- **THE BARS ARE NOT IN THE FILE, AND THAT IS THE POINT** — `hero.sit` runs `makeWhole` before the write. The
  SHEET is out for the same reason: it is `ptree.Bonus.sheet()` of the tree below, re-derived on the way in.
- **IT IS GATHERED AND SCATTERED THROUGH ONE VIEW** (`save.Slot`, `game.slotOf`) — the save file owns no game
  state and reaches for nothing. Parsing goes into a `save.Data` on the stack FIRST and is committed only if the
  whole file read.
- **A LOAD LANDS IN A FRESH WORLD AND THEN OVERWRITES IT** (`game.loadGame`) — every array the file does not
  mention is at what a NEW game has. **The order is load-bearing**: `beginGame` sizes `chests.n` off the map and
  rebuilds the trigger ORDER, both of which the file writes into and neither of which it carries. **`beginGame`
  IS THE ONE ANSWER TO "WHAT IS A FRESH GAME"** — `Game.init` and New Game both come through it.
- **A DEV RUN WRITES `devsave<n>`, NEVER THE PLAYED SHELF** (`save.useDevShelf`, set once in `game.run`). `--map`
  and `--shot` used the same three filenames: one rest at a test map's bonfire overwrote `save1.dat`, and since
  the file then named a map the shipping boot cannot match, the picker showed that slot EMPTY and New Game
  finished the character off. Every reader and writer goes through `path`/`shotPath`.
- **THE THUMBNAIL IS A POST-DRAW GATE, NOT A DECISION AT THE EDGE** (`game.takeSlotShot`) — `justEntered` fires
  at the BOTTOM of the fade-in where the screen is black, so what is OWED and when it can be PAID are different
  frames. Taken after the world is drawn and before the HUD and the fire's list. The harness calls the same
  function at the same point (`shots.bonfireShoot`), which is the only thing proving the grab works.
- **THE BOOT SCREEN IS ITS OWN SCREEN, not the pause card with different rows** — New Game / Load Game / Options
  / Editor / Quit, over a live 3D backdrop the camera walks slowly round. **IT HAS NO BACK AND NO CONTINUE**, and
  Select/Start are refused while it is up (`Menu.booting`) rather than gated at each call site. **QUIT IS ITS
  ROW**; from inside a game the way out is `Back to Title`. It stands away from the tower (`BOOT_AT_X/Z`).
- **`menu.home` IS WHICH ROOT A SUB-SCREEN RETURNS TO** — Options hangs off both cards, so a hard `.main` dropped
  you into the pause menu of a game nobody had started.
- **THE BOOT CAMERA IS ASKED FOR AFTER `menu.update`, NEVER BEFORE** — `dist`/`pitch` are the PLAYER's zoom and
  tilt and nothing in play resets them, so stamping the title framing on the frame New Game was pressed handed
  the new character a camera seven metres back.
- **BOTH ROWS ASK WHICH SLOT.** **A SLOT CAN BE THROWN AWAY, AND IT IS THE ONLY PRESS IN THE GAME THAT DESTROYS
  ANYTHING** — armed on one button (`hud.BTN_QUICK`) and done on a SECOND, the ordinary Confirm, because by then
  the row has become the question. Walking off the row, Back, or re-opening the picker all disarm it. **BOTH
  FILES GO** (`save.erase`). The menu holds no game state, so it hands `Action.deleteSlot` up.
- **A ROW THAT CANNOT BE PRESSED IS DRAWN SO** (`Menu.rowLive` + `Card.dim`) — one predicate read by the PRESS
  and by the picture. The cursor still lands on it: the reason is the footnote.
- **THE PICKER'S THREE TEXTURES LIVE NO LONGER THAN THE PICKER** (`loadShots`/`unloadShots`).

## Controls (`game.zig`)

Keyboard+mouse or gamepad; the pad follows **Elden Ring's default layout** (ER is the north star throughout).

- **WALK vs RUN:** the whole left-stick range is WALK (tilt scales walk speed only), and RUN is exclusively the
  hold-B / hold-Shift sprint. Gate run-only flourishes on `sprintB`, not the stick-speed `runB`.
- **Mouse:** hidden over the window and drives the camera, but NEVER locked/captured. Do NOT reintroduce
  `disableCursor`/pointer-lock.
- **Committed actions with an ER-style input queue** — an attack/roll pressed mid-action buffers in ONE slot
  (last press wins; a same-frame roll outranks attack) and fires at the earliest exit. A queued roll leaves in
  the direction HELD at fire time, not pressed.
- **INTERACT IS Y, EVERYWHERE** — `INTERACT_PAD`/`INTERACT_KEY`, and the keyboard mirrors the pad letter for
  letter so no crib ever has to name a key. It is the one face button ER leaves free: A is the jump, B the roll,
  X the quick item. The dialog panel takes it on top of the menu Confirm.
- **Guard or CAST:** hold L1/LB or RMB — the button belongs to the HAND, not the shield. **Aim or PARRY:** L2 is
  that same hand's SKILL slot, a raised bow aiming on the HELD level and boards parrying on the PRESSED edge.
- **Cross/A = JUMP** (keyboard `V`). Not a clash with the menu Confirm: every screen that takes Confirm holds
  the world still. `hud.BTN_JUMP` is named apart from `BTN_CONFIRM` because a rebind of one is not a rebind of
  the other.
- **A LADDER TAKES INTERACT AND THEN THE STICK, AND NOTHING ELSE** — forward is up whichever way the lens
  points, since the camera does not steer a ladder.
- **THE RIG TILTS ONTO WHAT IT IS LOCKED TO** (`game.lockPitch`) — the boom's pitch IS the view's, so the right
  number is the angle from the EYE down to the mark, measured off the LIVE eye rather than solved, which makes
  it a convergent feedback loop (gain `boom / (boom + range)`) that `camera.aim`'s ease damps. It is why
  `camera.PITCH_MIN` is −0.38. **THE TILT UP IS EARNED BY HEIGHT *AND* BY CLOSENESS**, and it is a SHARE rather
  than a switch (`lockTiltShare`, the product of two smoothsteps so neither gate can step). **DOWN IS FREE; UP
  IS EARNED** (`LOCK_TILT_TALL`) — the up half is gated on how far the creature reaches into the sky OFF ITS OWN
  FEET (`topWorld`), which keeps a kobold standing on a rise a kobold.
- **Lock-on:** R3 / middle mouse; a flick cycles; suspended entirely while aiming. Two ER exceptions: a hold-B
  sprint faces TRAVEL, and an attack's recovery tail re-squares (`ATK_RETRACK`). **YOU CANNOT FIX ON WHAT YOU
  CANNOT SEE** (`game.canSee`), but a HELD lock fades rather than switching (`LOCK_BLIND_HOLD`). **THE FLICK
  WALKS A LINE** (`game.stepPart`, `FoeRef.part`) — every point this body offers in part order, then the next
  body over at ITS first point, and back the same way, arriving on the last. R3 fixes on a body's first point.
  **A point is offered whether or not the kit in hand can reach it**: locked to the ogre's head, the sword swings
  at the head.

## Hard invariants & gotchas

### Coordinates and the frame

- **Coordinates:** ground is XZ, Y up. Hero faces +Z at yaw 0; `atan2(facing.x, facing.z)` is the facing angle.
- **Strafe sign:** the camera looks +Z from behind, so screen-right is world −X → `camera.rightXZ` MUST be
  `(−cos yaw, 0, sin yaw)`. Flipping it mirrors L/R walking.
- **VSYNC, not `setTargetFPS`** — `vsync_hint` before `initWindow`, no frame cap. `setTargetFPS` is a CPU-side
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

### Colour and material

- **The scene shader gammas output (`pow 1/2.2`): author dark colours near-black.**
- **Vertex alpha is the EMISSIVE channel** (255 = fully lit; lower = self-lit) — **…AND MATTER WANTS 248+, NOT
  206.** `lit = mix(lit, base*1.35, 1 - a)`, so alpha 206 puts 0.19 of the raw albedo on everything unlit: a 6%
  lift in SUN (nothing), and in SHADOW a floor the terminator cannot get under, so a whole creature authored at
  206 reads as one flat lump however well its albedo is solved. **Reserve the low alphas for the things that ARE
  LIGHT** — a throat, a flame, an eye.
- **A BIG SMOOTH MASS NEEDS A NEARLY-BLACK ALBEDO — and FORM BREAKS.** The hot key (×1.72) plus the gamma lift
  turns any mid-dark value pale on a large sunward face. The bigger the face, the darker it must start.
- **THREE STONE MATERIALS** — `.stone` is rubble masonry, matte (walls/towers/rubble); `.rock` is the natural cut and
  the cave shell, the same albedo TRIPLANAR off world position and with no gloss at all; `.marble` is dressed stone,
  veined, with the only real gloss besides steel and water, kept LOW (columns/arches/statues).
- **`gfx.Mat` IS APPEND-ONLY** — the shader branches on the raw ordinal 1..18 and comptime asserts pin the TAIL
  (water 9 through waterfall 18); pinning `water == 9` is what catches an insert below it. **The VERTEX-ANIMATED ids
  are bounded at BOTH ends** (`> 11.5 && < 13.5`, fog's `> 14.5 && < 15.5`): an open-ended test claims every id
  added after it, which is how `bark` went in and every trunk started climbing like an ember.
- **THE FLAME MATERIAL IS THE ONE THING DRAWN SEMI-TRANSPARENT BY ITS MATERIAL** (the faded hero under an aim is
  the one drawn so by a per-draw uniform). Opacity is graded off the emissive (`FLAME_A_CORE`→`FLAME_A_TIP`);
  depth WRITE stays on so tongues don't stack into a brighter core.
- **A LIGHT'S RADIUS MATTERS MORE THAN ITS BRIGHTNESS** — a 9 m torch in a 5×7 m chapel reaches every surface
  from every corner, so four summed to a flat wash however dim each was. **Fire has to POOL.**

### Geometry and the builder

- **BUILDER WINDING IS NOT CHECKED, AND FACE-DOWN GEOMETRY IS INVISIBLE.** A flat annulus swept outward-first
  points DOWN and raylib culls it. Sweep inner@a0 → inner@a1 → outer@a1 → outer@a0. For a ring, radial is the
  position direction and tangent is `(cos a, 0, sin a)`; for an arch ring at angle a, radial is
  `(−cos a, sin a, 0)`, tangent `(sin a, cos a, 0)`. **`addBox` also accepts a NON-PERPENDICULAR axis triple**
  and builds a skewed parallelepiped.
- **A cylinder is CAPLESS** — an open end shows its culled interior. Cap with `addDome` or an axis-flattened
  `addBlob`; a flat cap constrains the piece to a world axis.
- **A CURVED SHAFT DRAWS ITS CURL ONCE AND APPLIES IT EVERY SEGMENT.** Re-rolled per segment it wanders, and a
  wander made of straight capsules is a chain of elbows. Total arc is per-segment curl TIMES segment count, so
  moving either the length or the count re-brackets the curl.
- **REPEATED BIG PROPS NEED VARIANTS** — one mesh placed sixty times reads as a periodic pattern, and yaw and
  scale do not hide it. The three `bigtree` kinds and six `cliff` kinds exist for this, drawn through an op's
  weighted `mix=`. **Long-wavelength variation beats per-instance noise.**
- **Prototype models/meshes are permanent** (CPU arrays stay attached and leak at exit — fine). Don't
  `unloadModel` them. **TERRAIN TILES are the one exception, and cost two crashes:**
  - **`gfx`'s mesh allocator MUST be `raw_c_allocator`, not `c_allocator`** — raylib frees mesh CPU arrays with
    libc `free()` and `std.heap.c_allocator` does not hand out malloc pointers on Windows, so freeing one frees
    an interior pointer. Heap corruption, surfacing as `0xC0000374` with no stack.
  - **A MODEL'S MATERIAL CARRIES THE SCENE SHADER, AND ONLY THE PINNED raylib SPARES IT** — go through
    `env.unloadTerrain`, which points the material at raylib's default shader id first. The bundled raylib 5.5
    `UnloadModel` frees `materials[i].maps` and never calls `UnloadMaterial`, so today the swap is belt to the
    braces — but `UnloadMaterial` unloads any shader that is not the default one, and a raylib that routed
    through it took the scene shader out from under the whole frame.

### Particles

- **A MOTE IS A CAMERA-FACING TEXTURED BILLBOARD, NEVER A SOLID SPHERE** (`foe.drawParticles`, `foe.setLens`).
  `gfx/particleart.zig` builds one seeded atlas with four variants per style; `Particle.style` picks the shape
  and legacy emitters infer matter, haze, spark or blood from their properties. Alpha MATTER sorts back to front
  within each pool, then additive LIGHT; depth TESTED, never WRITTEN. **Reuse `foe.drawCloud`, `drawAura` and
  `contactFlash`** rather than adding sphere clouds or another contact emitter. `--shot --shot-only
  particles_study` and `docs/PARTICLE_PASS.md` cover the pass.
- **A POOL NOBODY CAN SEE MAY NOT BE DRAWN** (`foe.motesVisible`) — not for the per-mote cost but for the COUNT:
  twelve chaos clouds at 132 motes each still walk their whole array. The gate is a REACH and a HEMISPHERE and
  **it is not the frustum and may never become one.** A pool the lens is standing INSIDE always draws.
  - **AND IT IS NOT GATED ON THE EMITTER BEING ALIVE** — a cloud ticks its motes past its own death, so a puff
    laid on the last frame still fades out.
  - **IT IS ASKED OF THE MOTE, SO IT IS ON ALL 40 CALL SITES** — `drawParticles` scans for one visible mote
    before it binds anything, and `drawPass` asks again per mote. A per-CREATURE reach was never the way in:
    guessed too tight it clips a mote you could see, which is the one thing this gate may not do.
    **`tickParticles` stays ungated every frame for every body and always must** — a mote off screen has to keep
    moving.
- **A RING THAT OVERWRITES ITS OLDEST DOES IT SILENTLY**, so its size is arithmetic over what feeds it (every
  emitter's worst frame), asserted at comptime — never a round number that looked big enough.

### Shaders and the retro pass

- **GLSL RESERVED WORDS ARE NOT ONLY THE OBVIOUS ONES.** A local named `patch` compiled everywhere the author
  tested and failed on Intel, which enforces it at `#version 330`. `layout`, `subroutine` and friends are the
  same trap, and a scene shader that fails to compile is a hard startup panic.
- **Fullscreen shader passes must build ray/UV from `gl_FragCoord`** + a resolution uniform when drawn via
  `drawRectangle` — raylib maps rectangle texcoords to the tiny shapes-texture rect, so `fragTexCoord` is
  effectively CONSTANT. `drawTexturePro` blits are fine.
- **Retro pass contract:** with any filter active the frame renders into `Retro.rt` then blits through the
  combined shader; vignette, HUD and menu draw AFTER the blit. All-zero = bypassed entirely.
- **THE RETRO RT IS `GL_NEAREST`, AND PIXELATE POINT-SAMPLES IT.** `sceneTap` box-filters the block (`PIX_BOX`)
  instead of keeping one pixel of four, which is a TRADE — the twinkle IS a hard edge crossing a pixel boundary.
  **Sub-pixel filter offsets snap under nearest**, so the chroma fringe's offset snaps to whole BLOCKS.
- **THE FOG GATE IS A VEIL** (`props.foggate`, `propfx.fogGateMesh`, `Mat.fog`) — laid down in `env.drawVeils`
  AFTER everything opaque, because its own depth write at the head of the sheet is a rectangle of missing world
  behind it. `build` is the two threshold stones and the sheet is the veil; `solid` is TRUE. **ITS HEIGHT
  FRACTION RIDES `animY` AND IS READ TWICE** — the vertex billow in the VS and the fade in the FS — and it has
  to INTERPOLATE across a cell (`Builder.quadFadeAnim`), constant per cell it steps. **And the height the fade
  dies at WANDERS** per world column, over time: a few percent of alpha over something this bright is still a
  straight edge. **ITS VERTEX ALPHA IS LEFT NEAR-SOLID ON PURPOSE** — the scene shader reads `1 - fragColor.a`
  as EMISSIVE, so fading a translucent thing through the vertex colour makes it GLOW as it goes.

### UI

- **THE UI NAMES BUTTONS, NEVER KEYS.** Every prompt, crib and footer in the GAME shows the button that does the
  thing, DRAWN — `hud.Hint`, `hintRow`/`hintRowAt`, and the `padFace`/`padDpad`/`padBumper`/`padMenu`
  pictograms. No keyboard caption anywhere and no pad-vs-keyboard branch: one strip, whether a pad is plugged in
  or not. Keys still work. The glyphs live in `hud.zig` and not `uiart.zig` because a face button is a LETTER,
  and that file is the only path to draw text. **The EDITOR is the one exception.**
- **A BUTTON IS NAMED ONCE** — `hud.BTN_INTERACT`/`BTN_CONFIRM`/`BTN_BACK`/`BTN_QUICK`. `game.zig` binds off
  them and every crib draws off them, so a rebind moves the caption and the press together.
- **THE CURSOR IS A LEADING BAR, AND IT IS THE ONLY THING THAT MARKS A ROW** — `uiart.caret` draws it and
  `uiart.rowHilite` lays it under the wash, so a list cannot grow a second kind of cursor. A row too dim to take
  a wash draws the bar on its own at `CARET_DIM`: **the cursor may never be invisible on the row it is standing
  on.** The `<` `>` PAIR ON A GAUGE stays — that is "this row adjusts", not "you are here".
- **All UI text goes through `hud.text`/`textW`**, in **Balthazar** (`assets/`, OFL). **THE ATLAS IS ASCII-ONLY**
  — a `·` or `—` renders as tofu, in the game and in every save file. One face only.
- **SIZES COME FROM `hud`'s TYPE SCALE** (`TITLE`/`BODY`/`SMALL`/`HINT`/`TINY`, plus `MONO` for the editor),
  never a literal at the call site; rows step by `hud.lineH(size)`. The atlas resolution must stay ABOVE the
  largest size drawn, and the drop shadow's offset scales with the size.
- **HUD colours are LITERAL screen values** — drawn after the retro blit, outside the scene shader.
- **THE CHROME FADES AS ONE PICTURE, NOT AS A LIST OF THINGS THAT EACH KNOW AN ALPHA**
  (`hud.beginChrome`/`endChrome`, `game.HUD_FADE_DUR`, read off `hero.deathT`). Composited through a target
  because the alternative is threading a factor through every literal in `hud.zig` plus `uiart`'s rules and the
  `itemart` pictures. The target is only taken WHILE a fade runs — at full chrome `beginChrome` refuses. **The
  BANNER is not chrome** and is laid down after `endChrome`.

### Audio

- **raylib's `SetSoundPan` IS THE LEFT CHANNEL'S GAIN, not a position.** The mixer is `left = pan; right = 1 -
  pan`, so **`pan = 1.0` is hard LEFT**. `audio.panFor` is the only place the sign is decided and a test pins
  it. The pan law is `0.5·x·(3 − x²)`, so a hard-panned sound is ~3.2 dB louder in its own ear than a centred one.
- **`master` NORMALIZES each voice** (`norm`), so a layer's `amp` sets its BALANCE inside the voice and only
  `BANK.gain` sets how loud it is. **THE FIGHT IS ONE BAND** — combat rows above `BATTLE_FLOOR` are pulled
  geometrically toward the soft end, halving the spread in dB. **Retune by moving the FLOOR, not by pushing one
  row back up**; a test pins the ratio and the orderings.
- **THE VOLUME IS RESERVED FOR WHAT IS ABOUT TO HIT YOU** — a creature's committed arrival outranks its own
  movement noise (lunge over hop, slam over step, stab over wingbeat, swing over creak) and the tells sit past
  the midpoint of the band. **TEXTURE GOES AT OR UNDER THE FLOOR**, which takes it out of the band entirely.
- **TEXTURE IS THINNED IN COUNT, NOT JUST IN LEVEL** — `leechfly.DRINK_EVERY`, `rooted.CREAK_EVERY`. The one
  cadence that MAY NOT be thinned is `leechfly.WHINE_EVERY`.
- **THE FAMILY LEVEL IS `TRIM_COMBAT`, NOT THE FLOOR** — the floor moves only the `battle()` band. **And the
  fight is rolled off the top** (`COMBAT_TREBLE`, one pole at bake, UNDER the player's rack so a dial still sits
  on top of it).
- **The sound filter rack is BAKE-TIME** — raylib cannot filter a playing voice, but every voice is synthesized,
  so a dial re-renders that family (coalesced by `FX_SETTLE`). A bake STOPS every take before freeing any of it.
  **IT LIVES IN THE EDITOR, beside the JUKEBOX** — an authoring tool rather than a setting. Eleven dials ending
  in the EQ pair, applied LAST. The RETRO rack stays in the menu; that one is a LOOK the player picks.
- **THE BANK RENDERS ON A WORKER THREAD, AND ONLY RENDERS** (`sfx.bakeAll`) — boot loads the two streams and
  spawns it, so `sfx.init` is ~250 ms instead of 2.7 s in Debug. The worker owns `work`, `tape` and `pcm` and
  pushes PCM onto `queue`; `pump` uploads finished takes on the MAIN thread, because raylib's audio buffer list
  is touched from one thread only. A voice is silent until its first take is uploaded. Every main-thread path
  that synthesises or frees a row calls `awaitBake` first, which joins the worker and drains the queue.
- **THE BENCH EDITS ONE VOICE, NOT JUST A FAMILY.** `BANK` is the ORIGINAL and never moves; `live` is the copy
  every play path reads and the only thing the editor writes, **so revert is free and cannot be lost**.
  `settings.cfg` carries the DIFFERENCE only. Five dials answer under the finger; the eleven filters are
  bake-time. **`vars` and `poly` are NOT on the bench** — they size the alias table `freeRow` walks to unload a
  row, so a dial that moved either between a bake and its free would leak or double-free; they, `mix`, `id` and
  `make` are read from `BANK` everywhere and have no setter, pinned by a test.

## Gaps

- **Bone Knight:** no fighting stance — `poseUpper` sets no leg pose while standing, so `legChain` gives him
  straight legs and rest-offset feet through either stroke. It cannot be bolted on AFTER `legChain` (that is the
  hand that levels the ankle) and a bespoke walk is forbidden, so the stance has to go THROUGH `legChain` —
  every creature's change, not his. No RIPOSTE behind the parry. His arena has a `foggate` but no `arena:` row.
- **Necromancer:** no `necro_*` voice family (borrows the shade's, the wand's and the skeletons').
- **Combat:** no criticals, no guard counter, no AR × motion-value damage (flat constants). Nothing scales a
  cast. What carries no parry window says why at its own impact site, and the `game.NO_PARRY` pairing is
  comptime-enforced both ways.
- **The jump exists but little hangs off it** — no jump ATTACK, and no creature's move misses him for being over
  it (a per-move height would be authored at each `toImpact` the way a parry window is).
- **Souls buy levels and nothing else** — COIN is the other purse and the counter is what takes it. The tree is
  81 nodes with no respec, no jewel sockets, no second grant on a node. Every attribute is raised by at least
  one node (test-pinned) and none is inert; `stats.inert` stays and answers false for all seven, because the
  next attribute arrives dead the way LUCK did.
- **Ailments:** ten meters and no PANEL — `combat.ailSays` writes one line of mechanic per row and nothing calls
  it, so the meters explain themselves nowhere but in `item.effect`'s own sentence.
- **Equipment:** the **WARBOW and the DOOR are still the plain bow and the small shield** (the door has a mesh to
  borrow, the warbow is the bow at another scale). **NOTHING WORN SHOWS ON HIS BODY AT ALL** — helm, coat, belt,
  boots and both rings are a number, a bag picture and a socket caption. The crock lands with no burst FX; the
  tallowed blade shows nothing on the sword.
- **Rig:** no foot IK — `rx(bodyPitch)` rotates about the WORLD ORIGIN, so a deep lean levers a forward-swung
  foot down and feet clip a few cm on slopes. The roll has front-loaded i-frames but no collision. One leg-cycle
  is reused across run and sprint.
- **Elevation is authored but sparsely used** — terrain casts no shadows (the painted faces do), painted water
  is one level plane.
- **The script layer is foundations only, but it is AUTHORABLE** (`editor.drawScriptModal`) — triggers, their
  conditions and their actions are made, named, re-kinded and thrown away from a MODAL rather than a map layer,
  because a trigger is not a place. Still hand-written: the DIALOG trees themselves, and the flag/counter/timer
  TABLES (the modal cycles the names a map already declares and cannot coin a new one). Three `NpcKind`. No
  quest log, no journal.
