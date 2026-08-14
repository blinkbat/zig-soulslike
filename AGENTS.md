# AGENTS.md — zig-soulslike

Third-person soulslike in **Zig 0.14.1 + raylib**, on the sibling `../zig-rts` engine
(procedural-mesh `Builder`, single-sun shadow-map pipeline). README covers what exists.

`docs/ELDEN_RING.md` is the systems reference and is **PURE Elden Ring** — real mechanics, real
numbers, nothing about this game. No "how this maps to our build", no "we deviate" asides. Our own
mechanics and tunings go here, in the README, or in the code.

Keep this file lean. Prefer no comments in code — succinct ones for novel/edge cases only.
Reuse existing helpers before adding code. Don't make ad-hoc product/design decisions: ask.
The owner drives the design; implement what's asked and nothing extra.
Don't commit, push, or create branches unless explicitly asked.

## The laws (owner's, non-negotiable)

- **NO HITSTOP. EVER.** No freeze-frames, no time-dilation on impact, no dt zeroing. Impact weight
  comes from shake + rumble + FX + huge reaction anims, never from stealing time from the player.
- **ZERO INPUT LAG.** The stick maps straight to ground speed every frame. Posture/gait blends may
  smooth the VISUALS only, and only fast (~0.1 s max).
- **REACTIONS ARE HUGE.** A flinch or stagger must be big and obvious, never a subtle lean. **A mass in
  motion OVERSHOOTS its rest and settles back onto it** — props and geometry included; a glide to a stop
  is what reads as weightless.
- **FLESH IS ROUND.** Organic mass = `addBlob`/`addCapsule`; `addCube`/`addBox` is for iron, blades,
  cloth, masonry. Bare `addCylinder` leaves an open cut-pipe end — those rims and boxes are what read
  as BLOCKY however good the animation on top.
- **BIG BODIES HINGE AT THE WAIST, LEGS STAY PLANTED.** Route lean through SPINE/CHEST and leave the
  pelvis near-upright (`ogre.PELVIS_SHARE`); lean at the ROOT rotates the legs and reads as lurching.
  Braces take up in the knees, they don't squat.
- **WABI-SABI is the house style for ALL art.** Uneven sizes, asymmetry, leans, gaps. Author the
  variation in with a seeded `mathx.Rng` so builds stay deterministic. When a model or anim reads
  "dumb"/fake it is almost always too REGULAR. Cosmetic only — mechanics stay exact.
  **AT THE RIGHT SCALE, THOUGH: BETWEEN the instances, not ALONG one.** Two tones alternated segment by
  segment band a shaft like a barber's pole; the same two tones separating the VARIANTS read as three
  kinds of wood. Same dial, opposite result.
- **NOTHING DEAD IS STRAIGHT, AND NOTHING ENDS IN A POINT.** A limb drawn as one capsule to a needle
  tip is a spear, and a rosette of them is a hub of spokes. A dead limb leaves the bole on its axis,
  rises to an elbow, DROOPS off the line to a blunt snap of pale heartwood; twigs root on that outer
  half and carry on outward. `propwood.deadLimbInto` is the one both leafless trees call.
- **RELIEF IS SUBTLE.** Protruding detail breaks up a big mass with a few centimetres — a few PERCENT
  of the mass's radius, not a tenth. Sink the proud primitive most of the way in. Prefer more SIDES on
  the mass over more relief on top of it. Judge stand-off against the ASSEMBLED thing, not one mesh.
  Cut AMPLITUDE, never irregularity — "made regular" is the opposite failure, not the fix.
- **PACKED STONE HAS A CORE.** A row of blocks is only the FACING; without a substrate the joints leak
  sky. Overlap the facing well past its slot. `propart.courseInto`/`courseStack` do both.
- **DENSITY VARIES.** A flat per-region density is a carpet. `env.coverField` (two octaves of value
  noise) scales the region constant to nothing in clearings, and gates the structure belts too.
- **A REGION NEEDS THREE LAYERS** or it reads sparse however many props: ground-hugger, understorey,
  canopy. Dead growth is what stops it looking like a garden.

## Build & verify

- `zig` is NOT on PATH. Build with `build.cmd` / `build-release.cmd`; toolchain is
  `..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe`. `zig build test` runs unit tests.
- Verify rendering/animation by RUNNING `zig-out\bin\zig-soulslike.exe --shot` (or `shot.cmd`) and
  inspecting `shots\`. Never claim a visual change works without a shot. `shots\` is gitignored.
- Do NOT launch the interactive window to "check" — the owner plays it himself, and while he has it
  open the build cannot overwrite the exe. Build with `--prefix zig-out-dev` when it is locked.
- `--shot-props` renders every kind alone into `shots\props\`. For ONE model the editor's object
  viewer is faster.
- **Framing is part of the test.** Confirm the camera SHOWS the moving part before tuning. `follow`
  does not clamp pitch, so a small negative pitch at long `dist` puts the camera under the terrain;
  the camera ends at `target + back*dist`, so interior framings must be DERIVED from the room's
  extent; the shadow ortho box tracks the HERO, so `standHero` near your subject or there are no cast
  shadows. For a world change take a steep overhead map shot (`dist` near 55).
- **A SUBJECT MUST BE LIT, NOT JUST IN FRAME.** `gfx.SUN_DIR` puts the sun over the shoulder of a
  camera at **yaw ≈ 53** and into the lens of one at **≈ 233**. A foe turns to face the hero, so
  "photograph its front" means putting the sensed hero on the SUN's bearing and shooting from ~53;
  the 180-215 band puts its front in its own shadow.
- **Thin geometry needs a CROP.** Strings, nocked arrows, flutes, setts and HUD rims are invisible at
  1:1 — crop and zoom before calling one broken. Nearby clutter (quiver arrows by a skull) can
  masquerade as the part you are looking for.
  ```powershell
  Add-Type -AssemblyName System.Drawing
  $src=[System.Drawing.Bitmap]::FromFile("$PWD\shots\40_x.png")
  $crop=$src.Clone((New-Object System.Drawing.Rectangle 460,360,300,220), $src.PixelFormat)
  $big=New-Object System.Drawing.Bitmap 900,660; $g=[System.Drawing.Graphics]::FromImage($big)
  $g.InterpolationMode='NearestNeighbor'; $g.DrawImage($crop,0,0,900,660); $big.Save("$PWD\shots\crop.png")
  ```
- **JUDGE ALBEDO BY SAMPLING THE RENDER, NOT BY EYE.** Chain is albedo × 1.72 → linear → gamma 1/2.2.
  Screen ∝ albedo^(1/2.2), so a factor you want on screen is that factor^2.2 on the albedo — solve,
  don't guess, and `GetPixel` the subject AND what it stands against. Separate on HUE as well as
  value: everything outdoors here is warm.
- **THE SCREENSHOT GOES BEFORE `endDrawing`, NEVER AFTER** (`shots.snap`) — `endDrawing` swaps buffers
  and `takeScreenshot` reads the current one, so after the swap every capture is the previous frame.
- **The harness CLOSES THE MENU first** (`runShots`); the menu opens at launch and the HUD hides
  behind it.
- `--shot` PNGs are not byte-deterministic (flora wind + grain read `rl.getTime`) — verify visually,
  never by hash-diff.

## Module map

**How files are divided:** minimise TOKENS TO MAKE A CORRECT CHANGE, not file size. A 900-line file
whose contents change together is fine. Splits go where concerns genuinely part company.

| file | what |
| --- | --- |
| `main.zig` | entry; `--shot` headless harness |
| `game.zig` | window/loop, input, camera-relative movement, render orchestration, combat-beat feedback, YOU DIED. **A DEFAULTED FIELD ON `Game` MUST BE ASSIGNED IN `init`** — it is built from `alloc.create`, so `= .{}` on the field never runs and the field comes up as the fill byte. Silent, and it has bitten twice: `pack.n` as garbage, and the WHOLE DAY/NIGHT CYCLE dead because `g.day` was never assigned (rate 0 is a held clock; a NaN hour renders as the anchor) |
| `hero.zig` | THE HERO — FK skeleton, every animation, swept blade capsule, the guard, the bow, the wand. Start here |
| `camera.zig` | over-the-shoulder orbit rig, ground basis, trauma shake (live-loop only, so `--shot` stays deterministic) |
| `gfx.zig` | mesh `Builder`, scene shader, shadow depth pass, `Sky`, `Vignette`, `Mat` surface materials |
| `daynight.zig` | THE WORLD CLOCK — the sun/moon path, the hour's whole palette, and the anchor hour `--shot` pins |
| `shaders.zig` | every line of GLSL and nothing else; the contract with `gfx.zig` is written at its top |
| `worldfmt.zig` | THE MAP FORMAT — op vocabulary, zone/foe/**npc/trigger/dialog** tables, one comptime field table driving writer and parser |
| `trigger.zig` | THE TRIGGER MACHINE — SC1's conditions + actions, and the switches / counters / timers they compose through |
| `dialog.zig` | a conversation: the walk through one node tree, and the BG2-style panel it is read off |
| `npc.zig` | THE FOLK — the wanderer, on the hero's scaffold; idle set, gestures, roam, and the staff that plants with the far foot |
| `env.zig` | THE WORLD — terrain, op replay, `coverField`, uniform grid, cullers, occluder fade, lights |
| `editor.zig` | THE EDITOR (Menu > Editor), layered StarEdit-style; biggest file, next split candidate |
| `objview.zig` | object viewer + the JUKEBOX (sound auditioning) |
| `props.zig` | prop VOCABULARY + the `INFO` table (one row per kind); `displayName`/`group`/`stock` are exhaustive switches |
| `prop*.zig` | the meshes by family — `propart` (palette + weathering), `propruins`, `propbuild`, `propvillage`, `proprock`, `propwood`, `propflora`, `propfx` |
| `foe.zig` | THE FOE STANDARD — shared contract, `Blade`/`strike`/`weaponReaches`/`Blow`, `Trail` ribbon, particles, `Leash`, group plumbing |
| `frog.zig` | gaping toad + `Knot` |
| `archer.zig` | skeletal archer + `Line`; kite-only, arrows that stick and fade |
| `ogre.zig` | one-eyed ogre + `Grief`; 24 bones, high poise; slam (sometimes HELD at the top), side swipe (sometimes a RETURN chained off it), mid-range lunging DRIVE, jittered cooldowns; never strafes |
| `kobold.zig` | kobold warband + `Warband` — three roles of one creature (berserker/priest/slinger); the priest is why they are one group |
| `brood.zig` | brood mother, sacs, broodlings + `Brood`; guard not hunter, venom POOLS are the weapon — they POISON rather than burn |
| `warrior.zig` | skeletal warriors + `Muster` — shieldman (blocks, guard-breaks to one knee) and greatsword (uninterruptible slam) |
| `knight.zig` | THE BONE KNIGHT + `Vigil` — THE FIRST BOSS. Five metres of plate behind a TOWER SHIELD that does not break; you have to work round the side, and stood dead behind him HE FALLS OVER BACKWARD ON YOU, lies there, rolls onto his front and levers himself up |
| `shade.zig` | shades + `Haunt`; legless, hovers, 17 bones of its own. The one thing that drains FOCUS, the one thing that TELEPORTS |
| `leechfly.zig` | THE FIRST FLYER + `Swarm`; 15 bones, never lands. Drinks his HP through a beak and heals off what it takes, and ZOOMS out of sword reach |
| `rooted.zig` | THE TREE THAT ISN'T + `Grove`; a snag-mimic fixture — eyes open outside its reach, three limb strikes (slam/sweep/hook-drag), never moves |
| `shroom.zig` | the sporeling + `Cluster`; a squat mushroom that FLINGS itself and bursts a lingering spore cloud that POISONS (buildup, never damage). Sometimes it TRIPS instead — same gather, longer opening |
| `delver.zig` | THE DELVER + `Warrens` — the first thing that goes UNDER the world. It burrows, travels as a ridge of moving earth, and comes out TWO ways: BURSTING up through the ground under his feet with a small ring of a blow, or PLOUGHING a furrow down the line he is running along. On the surface, a claw that RETURNS. You cannot lock on to it while it is down |
| `necro.zig` | THE NECROMANCER + `Rite` — TALL, SKINNY, a dragging robe, a bone helm and a crooked staff. It never melees. A skeleton corpse inside its reach **STOPS DISSIPATING** (`heldOpen`) and it puts that body back up at part HP, once each; and it lays a **DELAYED ICE RUNE RING** on the ground where he is standing, which is the game's first and only source of COLD |
| `wolf.zig` | THE FIRST SPIRIT + `Pack` — what the BELL calls, and the one thing that fights ON HIS SIDE. NOT a foe (no `Leash`, its own `takeHit`, not in `FOE_GROUPS`) and the first QUADRUPED: 27 bones, and the gait is Hildebrand's two dials. Out past `RECALL_R` for `LOST_DWELL` and the BOND MOVES IT (`reappear` + `game.rematerialize`, the bell's own spot) — running home is what it tries first, and this is for when running cannot work |
| `combat.zig` | `Vitals` (HP + two-tier stagger + regen + death), `Stamina`, `Focus`, `Regen`, guarding rules, `HitOutcome`, `Elem`/`Resists`, `SpiritKind`/`SUMMON_MAX`. THE place to retune feel |
| `stats.zig` | the character sheet — seven attributes and the curves that make the bars |
| `passivetree.zig` | THE PASSIVE TREE — PoE2's, radially: three arms out of one hub, the gates, the `Bonus`, and the wheel it is drawn as |
| `item.zig` | item vocabulary, `Use`, the `Bag` |
| `chest.zig` | openable boxes; contents read off the placing op (`Op.loot`) |
| `rest.zig` | bonfire + campfire bonfire — the phase machine, the seat, and THE FIRE'S OWN SCREEN (its list, and the wheel behind Level Up); `isRestKind` is the one predicate |
| `souls.zig` | THE DROP — what a death leaves on the ground, the gold bloom it stands as, and the walk back for it |
| `hud.zig` | ER HUD, the PAD-GLYPH kit every prompt and crib is drawn with, and the ONLY path to draw/measure text. The three bars start at `BARS_X`, not `MARGIN` — the WORLD CLOCK'S dial has the corner (`dayDial`, drawn off `daynight.spanU`/`isDay`, so it cannot tell a different time than the light) |
| `ui.zig` | editor widget kit; `Ctx.anyHot` gates world clicks next frame |
| `uiart.zig` | chrome DRESSING shared by hud/menu/book/ui |
| `itemart.zig` | pictures of things — armaments and bag items as objects, sized by the caller |
| `icons.zig` | editor glyph set, drawn from primitives (vector, not an atlas) |
| `book.zig` | THE CHARACTER BOOK (pad START) — a Diablo paper doll + ten quick sockets, the bag, the sheet |
| `menu.zig` | THE BOOT SCREEN, the pause/debug menu, sound LEVELS, and the retro filter rack. The SOUND filter rack is not here — it is the editor's (`editor.rackPanel`) |
| `save.zig` | THE SLOTS — three files in the map's own `key: value` grammar, each with the picture the picker shows it by; written by sitting down at a fire and by nothing else |
| `audio.zig` | ~80 synthesized voices through one tape-style `master`; three submixes; read it as recipes |
| `rumble.zig` | XInput directly (raylib's GLFW backend stubs `SetGamepadVibration`); holds `PAD` |
| `shots.zig` | the headless harness — never in context while working on the loop |
| `collision.zig` | 2D XZ capsule/circle push-out, `blocksSight` |
| `mathx.zig` | ground-plane + vector/angle helpers, seeded `Rng` |
| `bake.zig` | one-way door that emitted the first map from the old code-authored regions |

## The hero rig (`hero.zig`)

- **Anatomy is real.** Bone lengths are fixed fractions of stature `H` (=1.8), Drillis & Contini via
  Winter. That is why proportions read as human.
- **18 bones** (`hero.N` — 17 joints plus the SWORD on the right wrist). `pose()` chains a world
  matrix per bone ONCE per frame; `draw()` only replays them, so shadow and silhouette always match.
- **Matrix convention (critical):** raylib `MatrixMultiply(a, b)` applies **a FIRST, then b**.
  Local = `mul(animRot, translate(offset))`; world = `mul(local, parentWorld)`. Backwards and the
  skeleton explodes.
- **Gaits are real.** Walk uses normative sagittal curves (Perry/Winter); run/sprint use Novacheck.
  Phase is driven by DISTANCE travelled, never time, so feet never skate.
- **THE 18-BONE SCAFFOLD IS SHARED** — `hero.N`/`PARENT`/`restHumanoid(hx, sx, stature)`, bone 17 the
  `HELD` weapon slot. Do not transcribe the joint layout into a new creature file. Only `hx`/`sx` and
  stature are honestly per-creature. The ogre stays off it on purpose (24 bones, three inserted ABOVE
  existing joints is a different layout, not a wider one).
- **HUMANOID ENEMIES REUSE THE HERO'S WALK/STRAFE** — `hero.advanceGait` + `hero.legChain`. Never
  author a bespoke walk; only the upper body is per-enemy. `legChain` is rig-size agnostic but a foe
  rig must keep the hero's leg indices (5..10) where they are.
- **A SCALE≠1 humanoid must scale its pelvis HEIGHT** (`pelvY*fs`) or the legs sink and it reads as a
  crouching blob.
- **THE UPPER BODY MUST ARTICULATE TOO — legs alone are not a gait.** Every walking humanoid owes a
  contralateral arm swing at full amplitude, elbows flexing through the forward half only, a shoulder
  girdle counter-rotating against the pelvis (`prot`), a trunk nod twice a stride, and a head that
  counter-rolls all of it. **Stagger the LAGS** — joints peaking on the same frame read as one welded
  block however big the amplitudes. `ogre.poseUpper` is the worked example.
- **FEET DO NOT SINK: level the ANKLE, never lift the BODY.** `legChain` measures the deepest sole
  corner against its `SolePatch` and rotates the ankle to clear. Whole-body corrections to a local
  problem read as a tremor. Also check the mesh: `addCube` takes a FULL size, `addCapsule`/`addBlob`
  take true RADII.
- **THE CROSSING SIDESTEP IS GEOMETRY, NOT TUNED ANGLES.** One symmetric ±`STRAFE_ABD` sweep per leg,
  half a cycle apart. A planted foot is WORLD-FIXED (its offset sweeps back linear in distance —
  holding a joint angle is only still in joint space, and that skate is what slid). Ask for foot
  heights and solve for the knee. Cadence has one dial: speed / `STRAFE_CYCLE`.

### Animation art direction

- **IDLE** — upright, still, alive: a slow breathing bob only.
- **WALK** — unhurried, grounded, near-upright (~3° lean). RESTRAINED arms (never both forearms out
  front — the "zombie arms" fail). Low hip sway, clear heel→toe stride, slight toe-out.
- **RUN** — low and aggressive: deep lean over a crouched pelvis. Arms pumping at ~90°, explicitly not
  swept-back "naruto" arms. Real flight phase.
- **SPRINT** — the run dialled up: deeper, lower, longer, faster. Falling forward and catching it.
- **ROLL** — dive into a tuck, ONE somersault over ONE shoulder about a low ball centre (banked,
  uneven, drifting roll to roll — cosmetic only), then a spin-free rise. No float.
- Blends: idle↔walk by a `moving` ease; walk↔run↔sprint by ground speed. Pose discontinuities
  cross-fade ~0.09 s; stances never snap while mechanics stay instant.

## Adding a foe (`foe.zig`)

- **Satisfy the contract:** `pos`, an embedded `combat.Vitals` (`vit`), `hits`, `justDied`, and the
  accessors `alive/dying/staggered/airborne/bodyR/hurtRadius/centerWorld/lockPoint/topWorld/
  flashFrac` + `tryHit(foe.Blade)`.
- **Reuse the behaviour.** `tryHit` is TWO shared calls and then what is yours:
  `foe.reached(self, blade) orelse return` (the swept test, the one-hit latch, the anti-cheese rouse, and the
  facing snap a `pierce` alone earns) then `foe.wounded(self, s, blade, .{ .light, .heavy })` (the hit count,
  the flash, the shove — returning whether the BLOW was heavy, which is what your blood and chips are sized
  off, never the REACTION). Only the shieldman has anything between the two, and that is the whole reason
  they are two. Damage and the reaction itself live in `foe.strike` under `reached`.
- **The shared body points.** `foe.bodyPoint(pos, h, scale, lift)` for a height on the creature's own axis —
  the hurt centre and the bar anchor — and `foe.markOn(bone, at)` for the reticle, which rides the POSE.
  `foe.stunCurve(t, heavy)` is the one reaction shape in the game; as five private copies its constants had
  already drifted four ways. (The kobold keeps its own on purpose: its flinch decays from full rather than
  swelling to it, which is a different animation and not drift.)
- **Build vitals with `combat.Vitals.initFoe`**, never `init` — that is the slow foe regen schedule.
- **`justDied` is a ONE-FRAME flag.** Reset at the TOP of `update`, set in `enterDeath`, apply the
  blade at the END. Applying it externally without the reset latches a nonstop rumble/shake.
- **EVERY BODY GOES OUT THE SAME WAY** (`foe.dissipate` + `foe.Dissolve`) — past its own `DEATH_DUR` the fall
  is over and it dissipates over `DISS_DUR` into gold motes rising and flakes of itself falling. The two
  DURATIONS are per-creature (a giant topples slower than a toad) and so is the `Dissolve` (rate, spread,
  rise, and the flake's colour — bone, chitin or hide); the SHAPE is not. As a private `emitDissolve` per
  creature it had drifted four ways over one effect at four sizes, and the ARCHER's had gone missing
  entirely — the one skeleton that shoots faded out into nothing while its twin shed bone. It reads FIELDS
  only (`fade`/`scale`/`pos`/`parts`/`fxHead`/`fxAccum`/`fxRng`, one spelling each), which is what lets it
  live in `foe.zig` at all: a creature's own emitter is private and nothing outside its file can call one.
  **The SHADE is the one exemption and it is written at its own `.dead`:** no collapse to be still after and
  nothing to shed, so it thins from the first frame instead.
- **A CORPSE IS NOT A COLLIDER.** `alive()` stays true through the collapse and dissipation, so every
  collision site asks `foe.corporeal` (`alive() and !dying()`) instead.
- **Group + register.** Wrap instances in a `Group` exposing `anyDied`/`totalHits`/`aliveCount`; its
  `reset` and `draw` are ONE-LINE DELEGATES to `foe.resetGroup`/`foe.drawGroup`. The draw's
  `setFlash(0)` tail is what a fourth copy would forget.
- **CROSS-CUTTING STATE IS EMBEDDED BY THE CREATURE AND STAMPED BY THE GAME** — its eyes (`Leash`), a
  hold on its feet (`combat.Root`). The creature reads the field; it never reaches out for the state.
- **DENYING MOVEMENT IS A POST-STEP GATE, NOT A GUARD AT EACH MOVER** (`foe.grip` + `defer grip.hold`,
  `game.gateTerrain`) — taken once at the end of `update`, because a creature grows movements (a dash, a
  leap, a shove off a blade, the next one nobody has written) and a per-site list is a list to forget
  one from. It takes ONE thing, the feet: the state machine still runs, the kit still swings, blows
  still land. Y is left alone — `game.groundActor` owns it and a held foe stands on its own ground.
- **A JUMP IS THE ONE THING THE GRIP REFUSES OUTRIGHT** (`foe.canLeap`) — a leap does not TRAVEL, it leaves the
  earth, and a creature held by the ankles cannot. Denying only its distance leaves it hopping on the spot
  inside a fist of roots, so a jump skill is gated where the move is CHOSEN, which is the one place a post-step
  gate cannot reach: the archer's backstep, the kobold's dash, the broodling's pounce, the greatsword's lunge,
  and the toad's hop AND lunge — every move a toad owns bar the jaws. Ask it of the move's own `hop`
  (`warrior.decide` folds it into `ready`, so `classify` cannot promise a strike the pick then refuses), never
  of one move by name. Already in the air when the grip closes, it finishes its arc: you cannot root what is
  not standing on anything.
- **STEERING ROUND WHAT IS IN THE WAY IS `foe.Nav`, STAMPED BY THE GAME** (`game.markWay`/`markWays`,
  `Leash`'s own arrangement). A creature owes a `nav` field and ONE method — `navWant(target)`, the point it is
  trying to walk at this frame, or null when it is not walking anywhere. `markWays` is folded over `FOE_GROUPS`
  and keyed off `@hasField(M, "nav")`, so gaining steering is a field and a method and never an edit there — and
  a test pins field ⟺ method, because both halves fail SILENTLY.
  - **It is STEERING, not a route.** No graph, nothing remembered: the stamp is a heading tested for the next
    couple of metres against `env.walkStep` (terrain, the deep) and `env.resolveActor` (the world's solids), and
    the fan is tried NEAREST-FIRST so an obstacle costs as little heading as it actually costs. What it answers
    is a body pressed into a wall for the rest of the fight; it does not claim more.
  - **The creature reads it in ONE place, and which one is its own movement's business.** `Nav.aim` for one that
    walks where it is LOOKING (the ogre turns his whole body — he never strafes); `Nav.along` for one that steps
    on a committed vector with its eyes still on him (the kobold, the shade, a kiting archer). A hop is bent at
    the CHOOSE (`frog`, `shroom`), never mid-arc.
  - **ONLY THE TRAVEL STATE.** A swing, a wind, a lunge, a leap and a pounce are committed: a heading bent under
    one of those aims the blow at the wall. And **the attack hop is left straight on purpose** — that one is the
    attack.
  - **A FLYER IS NEVER STEERED** (`gateTerrain`'s own `airborne` skip): the probe is the rule for FEET. The
    leechfly's answer is ALTITUDE, and steering it would refuse it the bank it may fly straight over.
  - **It is asked about whoever the creature is actually FIGHTING** (`Threat.aim`), never about the hero.
- **A BODY THE NECROMANCER CAN USE IS A `raisable`/`reraise` PAIR AND A `heldOpen` FIELD** — nothing else, and
  no edit to `game.markVigil`/`applyRaises`, which key off `@hasDecl` (`markWays`' rule). The field is named for
  what it does to the BODY rather than for the creature doing it: `necro.Vigil` is that creature's own field,
  and one name for both had `foe.dissipate`'s `@hasField` probe matching the caster too.
- **A multi-kind group answers for its own members** — `kind = null` in `FOE_GROUPS`, each member
  exposes `kind()`. A group with anything else on the field (sacs, acid) exposes `clear()`.
- **Anything the map can post is a `wf.FoeKind`, APPENDED never inserted** (editor unit brushes are
  pinned to that enum's order at comptime), plus `foeName`, a `unitTips` line, a `unitIcons` glyph and
  a `foeSwatch`. Several kinds of one creature go in as a CONTIGUOUS RUN, pinned at comptime.

### The Bone Knight (`knight.zig`) — the first BOSS, and the first thing you have to walk round

**THE TOWER SHIELD IS THE CREATURE.** Everything else about him exists to make you get behind it.

- **IT DOES NOT BREAK** (owner's call). The shieldman's guard is a stamina pool you empty and then punish;
  this one has no pool at all, because a shield that breaks turns "get behind him" into "hit the front until
  it falls off". It covers `TOWER_ARC` (105 deg either side, against a man's `combat.GUARD_ARC` of 65) and eats
  `TOWER_NEGATE` 0.93 — chipping him down from the front is possible, slow, and NEVER staggers him, because
  `combat.guardChip` carries no poise and no stance. Round the side is the only door to a punish window.
- **THE ONE COMPARISON IS SHARED** — `combat.withinArc(bearing, facing, arc)`, which `withinGuardArc` now
  calls. A second copy of how a bearing wraps is a second thing to get wrong.
- **HE IS OUT-TURNED, AND THAT IS THE WHOLE DESIGN** (`TURN_RATE` 0.58 rad/s). It is sized against the
  ANGULAR rate a walking player achieves round a body this wide, which is small because the radius is:
  at his own closest approach the hero circles him at 0.80 rad/s. At anything near a normal creature's turn
  (the ogre's 3.4) there is no back to get to, and a test brackets it from above.
- **A SWING IS ONLY AS ACCURATE AS THE THING ON THE END OF IT IS WIDE**, and both dials are measured against
  that (owner: the swings don't often hit). The door subtends 25 deg at the range it arrives, so: the DRIFT a
  commit sheds may not by itself carry the kit off a squared-up man — it was 32 deg against that 25 deg door,
  which missed a player who did nothing but walk — and `SWING_BEARING` may never exceed the kit's own
  subtended half-angle, or he throws a stroke at a place the door was never going to reach. `SWING_TURN` is
  still under `TURN_RATE`, because commitment has to cost him tracking or there is no window at all.
  **AND THE CLEAVE IS DELIBERATELY HELD TO NEITHER**: 1.18 s of commit on a blade's edge is the stroke you step
  out of, and the BASH is the punish for standing in front. A test pins the pair so they cannot become one
  move twice.
- **STOOD DEAD BEHIND HIM HE FALLS ON YOU.** `fallwind` is the one move in the game that steers AWAY from the
  hero — he stops tracking and brings his SPINE round onto you, which IS the tell — then goes over rigid. The
  crush is a STRIP down the line behind him, his own length long and his own shoulders wide, both DERIVED off
  the rig. It carries the biggest POISE and STANCE in the game; `game.BLOW_HEAVIEST` is a `@max` over it and
  the ogre's slam, so it stays right whichever of the two is currently heavier.
- **BUT IT IS NOT THE HARDEST HIT, BECAUSE IT IS THE HARDEST TO READ** (owner: it does too much damage). At 50
  it took 71% of a 70 HP bar off a move with no parry and no guard-break behind it; at 34 it sits under his own
  cleave AND the ogre's slam. Its price to the player is POSITION — the counter is the read and the roll — and
  its price to him is the longest opening in the game.
- **AND THE TELL IS THE LONGEST THING HE DOES** (owner: it needs more tell). `FALL_WIND_DUR` is bracketed from
  BELOW by every one of his own winds, not by `foe.TELL_MIN`: at 0.82 s it was SHORTER than the cleave's 1.18 s
  haul, so the one move the boards cannot answer was also the one you got least time to read. And it TRAVELS —
  a 24 deg rock forward onto his toes, then 30 deg hung back past the vertical, on a body that used to move
  twenty degrees across the whole gather.
- **AND THE AFTERMATH IS THE REWARD**: flat on his back for `DOWN_DUR`, over onto his front, then up off the
  shield — the longest opening in the game, and the door is down for all of it. The fall's cooldown outlasts
  getting up, so he cannot spend it twice running. Tests pin both halves.
- **HE ROLLS ONTO HIS FRONT AND STAYS THERE** (owner: the rolling / getting up part is bad). `rollAmt` used to
  UNWIND across the first 42% of the rise, so he heaved onto his face and rolled straight back onto his spine
  to stand up off it — the roll bought nothing and the move read as a crate rocking twice. Face-down with his
  head still behind his heels IS a body fallen FORWARD and turned about, so `turnAbout` writes it as exactly
  that: the yaw takes a half turn and the topple takes the sign. `Ry(180)·Rx(θ)` is `Rx(−θ)·Ry(180)`, so the
  swap is invisible on the frame it happens — which is the only reason it may be done at all — and a test pins
  the worst one-frame move of the helm across the whole move. He therefore comes up FACING the man he landed
  on. The roll also HEAVES (`ROLL_HUMP`) and throws an arm and the top leg over; both arms clamped and both
  legs straight is why it was a crate.
- **AND A BODY ALREADY ON THE GROUND CANNOT BE FLINCHED UPRIGHT.** A stun state carries no topple, so a heavy
  landing during the punish window snapped five metres of armour instantly vertical: the reward for reading the
  fall was the reward ending the moment you took it. The damage, flash, chips and stance all still land — only
  the state change is refused (`floored`). Death still goes through, and `enterDeath` records the topple the
  body was already at (`deathFrom`) so a corpse crumples from where it lay instead of standing up to fall over.
- **AN EFFECT'S PHASE IS ITS OWN DECAY, NOT A CLOCK BESIDE IT.** The landing's ring read `self.t`, which resets
  on every state change — and `.fall`→`.downed` lands inside the ring, snapping the whole body a quarter of a
  metre down its own length. Driven off `thud` itself it starts at 0, rings out over three half-cycles and ends
  at 0, blind to which state is holding it.
- **THE SAFE POCKET IS HIS QUARTER, NOT HIS BACK.** `FALL_SECTOR` (44 deg either side of dead-behind) is
  strictly outside `TOWER_ARC`, and the gap between them is where neither the door nor the strip reaches.
  A MOVE THAT CANNOT LAND IS NOT A DECISION: the strip is a strip, so it does not cover the whole flank.
- **THE FALL IS NOT PARRYABLE, AND THAT IS A DECISION** written at `parryable`. There is nothing to catch in
  five metres of armour going over, and boards that stopped one would be the answer to the move this creature
  is built round. Its counter is the ROLL and the read — which is why the tell is the longest in the game.
  The BASH and the CLEAVE carry ordinary `foe.PARRY_LEAD` windows.
- **ONE CHANNEL SAYS WHERE HIS BODY IS** (`toppleAmt`, and `rollAmt` beside it) — 0 standing, 1 flat, and
  NEGATIVE is forward, which is the only way he dies. The topple is a rotation of the ROOT matrix about the
  ground between his feet; the roll is `ry(180)` inside the rig, which is a spin on the spot standing and a
  barrel roll lying down. **So every world point on him comes off a POSED BONE, not a height off his feet**:
  `centerWorld` rides the pelvis, `lockPoint` the chest, `topWorld` the helm. A hurt sphere pinned to 2.9 m
  would hang in the air over a body lying on the ground.
- **AND THE DOOR MUST BE SEEN TO LEAVE** (`stowAmt`, the picture of `guardUp`, and a test pins them together).
  Both hands go onto the grip for a CLEAVE, so the shield turns edge-on and swings off his front — which is
  the other way in. The first pass had `guardUp` false through the whole stroke while the shield still sat
  square across his chest, which is a mechanic and a picture telling the player opposite things.
- **THE PLATE IS MATTE** (`PLATE` = `.plain`, `BRIGHT` = `.steel`). `gfx.Mat.steel` carries a deliberately
  blinding specular lobe — right on a blade, catastrophic on a face the size of a door: the whole suit went in
  as `.steel` and every portrait came back a blank white sheet. `.steel` is for what is SMALL AND PROUD.
- **AND THE IRON IS COLD** — the ogre's hue lesson, one creature along. At the world's neutral ironwork the
  door SAMPLED at 144,126,102 against ground at 117,107,91: barely a value apart and the same warm hue, so he
  read as one more slab of the cliffs. Everything outdoors here is warm, so a mass this size separates by
  being BLUE-BLACK. The shield's bands are ONE substance with a few points of value on them — three tones
  alternated band by band came out as a barber's pole across the biggest flat in the game.
- **THE DOOR IS SIZED BETWEEN TWO FAILURES**, and the numbers are MEASURED off the rig (a test pins them):
  under, it is a buckler on a giant; over, it hides the creature it exists to define. Authored symmetric about
  the grip its top edge landed at 5.58 m over his own 5.11 m crown. It is gripped HIGH like a pavise and hangs
  shoulder-to-shin, and it is pulled onto his CENTRE LINE — left where the hand is, it covers one leg.
  **ITS WIDTH IS `SHOULDER_HALF`, NOT A NUMBER** (owner: it does not cover enough). Chosen at 0.165·H it was
  1.75 m across a body 2.29 m over the pauldrons — a door narrower than the man behind it, so his own shoulders
  stood outside it and the front was never actually shut.
- **AND IT IS HELD AGAINST HIM** (owner, twice: it has to keep the shield close to the body if it is going to
  block all frontal). MOST OF THAT IS THE ARM, NOT THE STANDOFF. `SH_STANDOFF` came 0.108·H → 0.062·H → 0.028·H
  and the door was still 1.6 m clear of his cuirass, because `GUARD_SH` 52 held the shield HAND 1.8 m out in
  front of his own chest bone: the standoff is measured off the fist, so it can only ever be the last few
  centimetres. The shoulder comes down out of the reach and the elbow folds the forearm ACROSS his chest
  instead of out in front of it, which leaves 0.63 m of daylight — about a folded fist, and as close as a
  centre-gripped door can physically come. The test now brackets it from BOTH sides and measures off the
  CUIRASS FACE: the old one asked only that the hub stood past 0.8 of his ground FOOTPRINT, which is a fact
  about his feet and not his chest, and it PINNED the door at arm's length while passing.
  **AND EVERY POSE THAT LERPS OFF `GUARD_*` MOVES WITH IT** — `BASH_WIND_*` are the same hauls re-based (an
  absolute wind target silently loses its whole gather when the guard moves under it), `FALL_SH`/`FALL_EL` were
  a fold inward at the old guard and an OPEN at the new one, and `BASH.reachOut` is re-MEASURED at 0.74 because
  the ram now starts 0.75 m nearer his body.
- **AND THE SWORD RIDES ON HIS OWN SIDE, NOT ACROSS HIS BACK** (owner: the sword holding anim is bad). At
  sh−20/el−16/abd24 the fist sat 1.68 m out — half a metre OUTSIDE his own shoulder — and the point crossed the
  midline, so 2.9 m of blade lay diagonally over his spine with an end sticking out either flank. The arm comes
  IN to the shoulder line and UP; the blade then stands behind his sword-side pauldron and leans back over it.
  The old test allowed it: `@abs(tip.x) < bodyR` is his ground FOOTPRINT (1.77 m), so it passed on a point
  already over onto his shield side. It now pins the point to his own side of the midline and inside his own
  shoulders, and the FIST with it.
- **A WAKE ON A 2.9 m BLADE IS NOT THE WARRIOR'S WAKE.** `TRAIL_ROOT`/`LIFE`/`PEAK` went in as his numbers on
  a blade three times as long through a 110 deg sweep and came back an opaque pale SHEET wider and taller than
  the knight — the feedback law's other failure, and it hid the swing completely for four frames of the stroke.
  The AREA is not negotiable on an edge that long, so the dials that are: span the outer HALF of the blade,
  live well INSIDE the strike so the whole arc is never resident at once, and carry half the alpha.
- **AND THE ACCENTS ARE SOLVED TOO, NOT JUST THE PLATE.** The albedo law was applied to the cuirass and not to
  what is bolted to it: `propart.RUST` is right on a prop's fleck and, on rim capsules 2.5 m long, sampled at
  178,129,83 — over the ground (129,117,100) AND his own plate (109,107,109). That inverts the hierarchy the
  plate was solved for and competes with the ember, so he has his OWN rust, solved down the chain to ~120.
- **THE PICTURE OF THE GATHER IS THE TELL** (owner: the telegraphs need more). The bash's wind moved the
  shoulder 22 deg and the lean 16 across its whole length — a frame-by-frame strip showed six frames in which
  nothing visibly happened, which is a committed action that shows nothing. Every channel now travels hard
  AWAY from where the strike takes it, and the wind is long enough to be read rather than just to be large.
- **JUDGE A STROKE ON A STRIP, AND SPEND THE FRAMES WHERE THE MOTION IS** (`shots.knightStrokeStrips`). Two
  frames per swing show none of this. And an EVEN walk over the move is a trap: the cleave is 1.18 s of wind to
  0.26 s of strike, so evenly spaced frames put six in the wind and one in the stroke — which reads as a swing
  that never travels when what it is actually showing is the held shiver at the top.
- **EVERY REACH IS MEASURED, NOT ARGUED.** A test walks each stroke frame by frame, reads the posed kit and
  brackets the declared `reachOut` against where it actually arrives — which is what caught a 0.84·H blade
  landing 6.9 m off his axis, out past the ogre's whole sweep.
- **HE HAS NO VOICE OF HIS OWN YET.** He borrows `ogre_step`/`ogre_slam`/`ogre_heave`/`ogre_roar` and the
  skeletons' `bone_hurt`/`bone_die`. `ogre_slam` is the game's one "heavy thing meets earth" voice and is
  right for the body landing; the rest are placeholders for a `knight_*` family.

### The delver (`delver.zig`) — the first thing that goes UNDER the world

**MOST OF THE FIGHT HAPPENS WHERE THE SWORD CANNOT GO.** Everything else on this field is answered by looking
at it; this one spends its time as a ridge of moving earth and arrives THROUGH THE GROUND under his boots.

- **SUBMERGED IT CANNOT BE STRUCK, AND THAT IS GEOMETRY RATHER THAN A GUARD IN `tryHit`.** `depth` rides as a
  NEGATIVE lift through `foe.bodyPoint`, so the hurt sphere, the bar and the reticle all sink with the body and
  the swept test refuses it on its own. A comptime assert pins the clearance; a creature that needed a special
  case here would need one at every future site that swings anything.
- **`airborne()` IS TRUE WHILE IT IS DOWN** — it is UNDER the world's traffic rather than over it, and that is
  the same answer to every question that predicate is actually asked in `game.zig`: no terrain riser rule, no
  shoulder from the hero or another body, no steering (it goes under what the probe would bend it round), no
  jaws from the wolf, no spirit handed to it. It is NOT exempt from `env.resolveActor` — burrow through a wall
  and there is nowhere to come back up from, which is the leechfly's own trade.
- **THE DIVE IS A LEAP AND THE ROOTS REFUSE IT** (`foe.canLeap`, the shade's blink and the leechfly's climb): it
  does not travel, it LEAVES THE EARTH — downward, which is the same thing to a creature held by the ankles.
  Gated at the choose AND re-asked at the launch, since a root closing during the wind arrives after the
  decision. That is the wand's whole argument against this creature.
- **IT STAYS DOWN** (owner's call, `UNDER_MIN` 2.6 s) whatever it finds on the way, and never past `UNDER_MAX`
  — a player who simply keeps walking must not end up fighting nothing at all.
- **THE BURROW HAS TWO WAYS OUT, AND THEY ANSWER TWO SITUATIONS.** Under him it BURSTS — a ring round the hole,
  and the counter is your feet. Out in front of him it PLOUGHS: the ridge stops turning, STRETCHES down the
  heading it already has (`moundLong`, not a bigger `moundR` — swelling is the surge's picture and drawing out
  is this one's, and as one dome at two sizes there was no read at all) and drives a furrow along the line at
  `PLOUGH_SPEED`, which is the only thing it owns that catches a sprint. Get off the MARK, or get off the LINE.
  Its patience exit is the plough too wherever he is in front of it: a surge at ground he left ten metres back
  is the move spent on nothing. Lighter than the burst on all three counts and a comptime assert pins that —
  `game.zig` splits the felt beat on `hit.stance >= BURST_HIT.stance`, so a plough that matched it would be
  felt as the ground opening under him.
- **THE CLAW COMES BACK** (`rake`). The surfaced window was one stroke on a two-second cooldown, so reading the
  burrow and punishing it was a trade you could not lose. The return is FASTER than the opener — that is the
  whole of it — still clears `foe.TELL_MIN`, is parryable on its own window, and is ROLLED rather than
  guaranteed and only thrown while he is still standing in it: a backhand at empty air announces that the
  punish was free after all.
- **YOU CANNOT LOCK ON TO IT WHILE IT IS UNDER** (owner's call). `hidden()` is the Rooted's own predicate, which
  `game.disguised` finds by `@hasDecl` — so a held lock drops, the flick skips it, a fresh press cannot take
  it, no floating bar hangs over the hole, the swing stops stooping at it and the wolf stops trying to bite two
  and a half metres of earth. It is `deep()` and not a clock of its own, because that is what `Model.draw`
  already hides the body behind: the lock lets go on exactly the frame there stops being anything to see, and
  the dive and the rise both keep it since it is right there and hittable in both.
- **THE SPOT IS COMMITTED THE FRAME THE MOUND STOPS.** Nothing moves for the whole tell: what the earth is doing
  IS where the blow lands, so the read is honest and the counter is your feet. A RUN or a ROLL clears the ring
  and a WALK deliberately does not — both bracketed by comptime asserts against the hero's own numbers.
- **AND THE TELL IS THE LONGEST THING IT DOES** (`SURGE_DUR` 1.15 s), on top of a mound that has been visible the
  whole way in: this is the final commit, not the whole warning. The Bone Knight's lesson one creature along —
  the move the boards cannot answer may not be the one you get least time to read.
- **THE BURST IS NOT PARRYABLE AND THE CLAW IS.** There is nothing to catch in the ground opening under you; its
  counter is the mound and the roll.
- **THE BLOW IS A RADIUS, NOT A SWEPT LIMB**, and its `from` is the hole itself — so stood dead on it there is
  no bearing and the boards cannot answer it (the zero-`fromDir` rule); caught at the rim, they can.
- **THE THIRD CHANNEL OF THE TELL IS THE PAD** (`Warrens.anySurged` -> `game.SHAKE_SURGE` + rumble). The mound and
  the noise are no use to a player whose camera is pointed at the horizon, and this is the one move in the game
  that arrives from a direction the lens cannot be turned toward.
- **THE MOUND IS NOT PART OF THE BODY.** It hangs off no bone: its matrix is built in WORLD space at the surface,
  because the body's own is metres under the ground by then. It is SIZED TO THE RING it announces — authored
  wider it hid the man standing on it — and it comes apart across the rise rather than vanishing on one frame.
- **PARTICLE COLOURS ARE LITERAL SCREEN VALUES WHERE MESH COLOURS ARE ALBEDOS** (`CLOD` against `SOIL`). Authored
  off the mesh palette the clods came back as a scatter of black dots hanging in the air.
- **A ROOT PITCH ROTATES ABOUT THE POINT ON THE GROUND**, so a body this long tipped for a drill drives one end
  through the floor — the hero's no-root-pitch trap, on a creature with no waist to hinge at instead. The root
  is lifted by exactly what the tip sinks, and the lift fades out with the depth.
- **AND THE HIDE IS COOL WHERE THE SOIL IS WARM.** Everything outdoors here is warm, so a brown digger on brown
  ground is a mass nobody can find. The numbers are SOLVED off a sampled render: the first pass at albedo 24 came
  back at 150 against ground at 127, a pale grey boulder with claws.
- **IT REARS TO STRIKE, and that is not a flourish.** Its shoulders sit at 0.40 m, so the rake only crosses a
  standing man at all because the rear is in the wind; held flat it topped out under his knee while
  `weaponReaches` still reported a hit.

### The necromancer (`necro.zig`) — the first thing that takes your work back

**IT NEVER TOUCHES YOU, AND IT IS THE PRIORITY TARGET ON ANY FIELD IT STANDS ON.** Every other creature here is
answered by fighting it; this one is answered by fighting it FIRST. 78 HP and 12 poise — it flinches off almost
anything — against 320 souls, which is dearer than a greatsword.

- **THE CORPSE IS THE MECHANIC, AND THE WINDOW HAD TO BE MADE TO EXIST.** A skeleton is `DEATH_DUR + DISS_DUR`
  = 2.05 s from the killing blow to its last mote, which will not hold a raise with a readable tell inside it —
  as a race against the dissolve the move would essentially never fire. So a body inside `RAISE_R` of a living
  necromancer **STOPS DISSIPATING** (`heldOpen`, stamped by `game.markVigil`, read by `foe.dissipate` through an
  `@hasField` opt-in so the eleven creatures nothing raises are untouched). **The held corpse is therefore the
  FIRST tell and it arrives before the cast**: every other body in the game goes to gold on its own clock, and
  one lying there NOT going is something the player can see without knowing yet what a necromancer is.
- **IT IS A PLACE, NOT A LIST.** Every flag is cleared and re-earned each frame off where the bodies actually
  lie, so walking the fight out of its reach releases the corpses on the frame it happens and killing things
  where it cannot reach never gives it anything. **And two of them cannot claim one body** — they are walked in
  order and an already-stamped corpse is skipped, so a pair cannot spend two casts on one skeleton.
- **A BODY MAY BE RAISED ONCE** (`wasRaised`, `shieldGone`'s arrangement) at `RAISE_HP_FRAC` of its HP, full
  poise and stance, into a light stun so it cannot swing out of the ground. Twice is a fight that cannot be won
  by killing things, which is the only thing the player is holding. **The shield does not come back**: whatever
  the player already broke off that body stays broken.
- **THE CREATURE ONLY REPORTS IT** (`raised`, a one-frame flag, and `raiseAt`) — `game.applyRaises` does the
  raising, because the corpse is in another group, in another array, of another type. `justDied`'s arrangement
  in the other direction. `foe.rekindle` is the shared re-arm and reads FIELDS ONLY, `dissipate`'s own reason;
  the STATE it comes up in cannot be shared and is each creature's own two lines.
- **THE RAISE IS THE LONGEST TELL IN THE GAME** (`RAISE_WIND` 1.90 s) and it is PLANTED for every frame of it,
  which is the whole punish window. It **turns to the BODY, not to him** — the one move besides the knight's
  fall that looks away from the hero, and that is what says WHERE as well as WHAT. **The spot is committed the
  frame the gather starts**, so a nearer corpse falling mid-tell cannot swing 1.9 s of announcement elsewhere.
- **AND THE ICE RUNE RING IS THE OTHER HALF** (owner's call), which is the delver's surge's law list over again:
  committed to the ground where he was standing, and it **OUTLIVES THE CASTER** — killing the thing after the
  cast does not un-cast it, because the ring is in the ground by then. Not parryable, and its blow carries the
  RING as its origin (`hitFrom`) rather than the caster, so stood on the mark there is no bearing at all and the
  boards cannot answer it. **`FROST_FUSE` is SOLVED, not chosen**: long enough that a WALK clears the rim from
  dead centre, which is where it parts company with the burst a walk deliberately cannot clear.
- **THE FUSE BURNS ROUND THE RING RATHER THAN FILLING IT.** Runes take one by one round the rim and the last one
  lighting IS the blow — a countdown legible from any bearing, and one you can COUNT rather than infer off a
  brightness ramp. **Built from `drawSphereEx` and nothing else**: `drawLine3D` is one pixel however close you
  stand, and a `drawTriangleStrip3D` annulus came back invisible on the render beside particles landing on the
  same spot on the same frame. Both drew NOTHING, twice, and neither failure was visible from the code.
- **THE MARK TAKES THE GROUND AT THE MARK, WHICH IS THE TARGET'S OWN `pos.y`** — never the caster's. `pos.y` IS
  the ground under an actor, so the target's is the height the ring has to be drawn at; the caster's is right
  for a point on its own body and wrong for a mark twelve metres away, where the two grounds differ by more
  than the ring's clearance and the whole thing is depth-culled under the turf.
- **TALL AND SKINNY IS TWO DIALS AND THE RATIO IS THE CLAIM** — stature through `SCALE`, and `restHumanoid`'s
  own `hx`/`sx` narrowed, which are the only numbers honestly per-creature on the shared scaffold. Either alone
  is satisfiable by the wrong creature: scaled up at the scaffold's width it is a big archer, narrowed without
  the height it is a child. A test measures stature over shoulder SPAN against the archer standing next to it.
- **THE DRAGGING HEM IS NOT A BONE** — it rides the ROOT through a lag matrix, the shield's own arrangement. It
  is a SPRING and not an ease: cloth on the ground is left behind and hauled after, so the lean opposes the
  travel, OVERSHOOTS its rest and settles onto it, and a test pins the overshoot because an ease can never
  produce one. **And the skirt panels are thin walls at the RIM**: `addBox` takes HALF-axes, so a radial extent
  of `r/2` centred at `r/2` spans from the axis out to the rim and every panel comes out a solid pie slice —
  the first pass was three stacked barrels and read as a chess pawn.
- **THE STAFF ARM MUST BE THE RIGHT ONE.** `heromod.PARENT[HELD]` is `WRR`, so the held slot hangs off that
  wrist and no other; authored on the left, the pole's matrix was built against a `wx[WRR]` nothing had written
  yet — undefined memory, and the whole staff transformed to a point at the world origin. `poseUpper` therefore
  poses that arm LAST, with the staff after its own wrist.
- **AND `staffTilt` IS 180-IS-PLUMB, the warriors' `wpnTilt` convention** — read as "degrees OFF plumb" the
  first pass authored 12 and drove 1.5 m of pole through the floor. **The fit bills the ARM but not the TRUNK**,
  so a pose that arches the spine pays for it at its own constant: `RAISE_LEAN` takes the chest back 22 degrees
  and the staff inherits every one, which laid it out diagonally across his front at the same number that
  stands it up at the carry. All three poses are MEASURED and bracketed — carry 16 deg with the ferrule down,
  raise 9 deg planted, frost 31 deg with the ferrule LIFTED, which is what keeps the two tells apart.
- **THE FROST NEEDS TWO PALETTES FOR ONE SUBSTANCE** — the delver's `CLOD`-against-`SOIL` law and the knight's
  `.steel`. `RIME_ALB` goes into meshes and runs through ×1.72 → gamma; `RIME` is drawn unlit and is a literal
  screen value. One constant for both blows out the staff head to a white knuckle or makes the ring grey grit.
- **AND THE ROBE'S HUE HAS TO BE LAID ON THICK, because the sun cancels it.** Authored at a value that looks
  decently blue in a swatch it SAMPLED dead neutral grey on the render — the key here is warm and multiplies
  through, so the blue channel has to run at better than twice the red in the ALBEDO to survive to the screen.
- **IT HAS NO VOICE OF ITS OWN YET.** It borrows the shade's `shade_reach`/`shade_gather`/`shade_touch`, the
  wand's `wand_charge`/`wand_cast` and the skeletons' `bone_hurt`/`bone_die` — placeholders for a `necro_*`
  family, the Bone Knight's gap one creature along.

### The leechfly (`leechfly.zig`) — the first thing that flies

**ITS HEIGHT IS THE WHOLE CREATURE.** `pos.y` is the ground under it like everything else's and `hover` is
what it is flying above that by — the shade's field, except this one MOVES, and every world point it has
(`centerWorld`, `lockPoint`, `topWorld`, the hurt sphere) is measured off `pos.y + hover`.

- **IT ZOOMS OUT OF SWORD REACH** (owner's whole point). Threatened, it climbs to `HOVER_HIGH` (4.6 m) in a
  third of a second, hangs there working round behind him, and dives back. The hero's blade sweeps a capsule
  off his own shoulder and cannot reach that; **an arrow can, and so can a bolt.** The climb takes the sword
  off the table and hands you the ranged kit, and that trade IS the fight.
- **THE CLIMB IS A LEAP, AND THE ROOTS REFUSE IT** (`wantsClimb` → `foe.canLeap`, the shade's blink rule). It
  does not travel, it leaves the earth. Rooted, the one thing keeping it alive is gone and the sword finally
  answers it — which is the wand's whole argument against this creature.
- **IT IS ALWAYS `airborne()`**, so the terrain gate never applies (a fly does not walk up slopes) and nothing
  on the ground shoulders it. It is NOT exempt from `env.resolveActor`: fly through a wall and there is
  nowhere to come back from.
- **THE FEED IS A BLOW AND THEN A HOLD, and they go down different channels.** The beak going in is a real
  `foe.Blow` — blockable, and it carries where it came from. The swallow after it is a DRIP (`game.leechSip`
  → `hero.burn`), billed per SECOND and scaled by `dt`. A shield answers the first and only the ROLL answers
  the second: `holds()` is re-asked every frame and it tests the height as well as the bearing, so getting
  out of the beak's own band is what breaks it.
- **IT HEALS OFF WHAT IT TAKES** (`LEECH_SHARE`, some of it and not all) — a flyer that heals for everything
  it drinks is a stalemate against a player with no bow. The belly (`gorge`) fills as it goes and STAYS
  full, so a fed one you failed to kill is a thing you can see you failed to kill.
- **AND THE EYES COME ALIGHT WHILE IT DRINKS** (owner's call). Drawn in `drawFx` as unlit spheres over the
  opaque pass, not lit in the mesh: vertex alpha is a FIXED emissive channel and cannot brighten, and
  brightening is the entire cue.
- **THE WHINE IS A RETRIGGER, not a loop** (`WHINE_EVERY`, the footfall idiom) — raylib cannot loop a
  synthesized take. The voice is cut a hair LONGER than its own period so consecutive takes overlap; gapped,
  a mosquito's note chatters on and off at 4 Hz, which is a helicopter.
- **A SWATTED FLY DROPS.** The stun states pull `hoverTo` down: the height sagging is most of what a hit on
  this creature looks like, and it is the window to hit it again in. Death is the hover running out from
  under it before `foe.dissipate` takes it.

## Combat

**The two sides are tuned SEPARATELY.** A stagger you inflict is a punish window you must be able to
walk into; a stagger you suffer is time taken off the player. Hence `FOE_*_STUN_DUR` well past the
hero's and `FOE_REGEN_*` far slower.

**NOBODY IS POISE-DAMAGED WHILE ALREADY REELING, EITHER SIDE** (owner's law). While a stun runs,
incoming poise is dropped; when it ends, poise goes back to FULL, both tiers. HP and direct STANCE
damage still land — you just cannot re-flinch something already flinching. `combat.Vitals` owns the
clock (`stunLeft`, armed by `beginStun`), and it ticks BEFORE the regen gate or a foe's `regenDelay`
outlasts the window and the immunity never lifts. A GUARD BREAK is the one door `hit()` misses —
`hero.enterStun` arms it.

**A DRIP IS NOT A BLOW.** Anything that HOLDS bills damage every frame (`Vitals.drip`), and a blow's
side effects cannot be billed at that rate: `hit` stamps the clock that gates the poise/stance refill,
so re-stamped every frame a hold that carries no poise would still deny a whole poise bar. Hence TWO
clocks — `sinceHit` gates the refill and only a blow moves it, `sinceHurt` is what the floating bar
reads and anything that takes HP moves it. One field cannot hold a gate shut and show a bar. **A drip
that KILLS is reported, not acted on** — only the creature knows how to die.

**A BLOW MAY TAKE THE BLUE BAR** (`combat.Hit.fp`) — the shade's touch, and the only thing in the game that
does. It is NOT part of `Hit.raw()`: what a shield's stamina bill and "which of two blows was worse" measure
is the WEIGHT of the thing that hit you, and a drain has none. `hero.takeHit` is the one place it is spent
(`Focus.drain` FLOORS, where `Focus.spend` refuses — a blow is not a purchase), and the guard chips it by the
same fraction it chips damage, because nothing the boards stop is stopped outright. Nothing but the hero
carries a `Focus`, so a foe handed one of these simply never reads the field.

**A RANGE GATE IS MEASURED FROM THE TARGET'S HIDE, NEVER ITS CENTRE** (`knight.triggerR` adds `HERO_REACH`;
`wolf.triggerR` adds the quarry's `bodyR`). `env.resolveActor` holds an attacker `bodyR + its own` out, so a
FLAT centre-to-centre range is unsatisfiable on anything broad: the wolf's jaws opened at 1.85 m while the
colliders held it 2.11 m off the Bone Knight, and it circled a creature it could never trigger on. The ogre
had 0.24 m of margin, which is why that one merely "struggled". Derived off the hide the margin is the same
1.5 m on every creature, which is the point. **AND HEIGHT IS A SEPARATE QUESTION FROM REACH, so it needs its
own test** — the knight's outward reach was measured and pinned from the first pass while nothing pinned how
LOW the kit got, and the bash's swept segment spanned only the middle 78% of the door: it bottomed at 1.29 m
against a hero whose chest is at 1.12 m, so three metres of iron arrived and the mechanic clipped his hair
while the mesh covered his shins. A "below his crown" assert passes on a blow that only touches hair; ask for
CHEST height. Both tests print their measurements, because the number is the finding.

**A TIMED STATUS REFRESHES, IT DOES NOT STACK** (`Root.grab`, `Regen.start`). Two clocks running on one
body is a state no bar and no animation can show.

**ONLY A SWING REACHES MORE THAN ONE BODY.** There are no area spells. A sorcery thrown into a warband picks
ONE victim — the locked foe, else the nearest to the mark (`game.rootVictim`) — so its own reach is a search,
never a blast, and the FX that says what it took is sized to the BODY (`combat.ROOT_GRIP_R`), not to the reach.
A ring drawn out to the search radius promises a hold on the neighbour the spell walked past.

**AN EFFECT'S CLOCK IS DERIVED FROM THE MECHANIC'S, NEVER PARALLEL TO IT** — what is standing on the
ground IS how long the hold has left. Two constants that can disagree eventually will. And when the
effect STAGGERS its parts, its container outlives the mechanic by that stagger, or the last part is cut
off mid-finish and pops away.

**FEEDBACK ON A CREATURE IS SIZED BETWEEN TWO FAILURES.** Under, it is scenery round the ankles; over,
it hides the creature it exists to point at. Judge the size against the CREATURE, never against the
hero who caused it.

**A FLOATING BAR TIMES OUT; THE FIXED ONE DOES NOT.** The target under the reticle keeps its numbers up
whether it was hit lately or not. It goes with the RETICLE, not `g.lock`, so a suspended lock takes the
bar down with the dot.

**AND IT MAY NOT CLIMB OUT OF THE FRAME** (`hud.FOE_CEIL`). Bars hang off `topWorld`, which is right at every
distance you can see the whole creature at and wrong the moment you close on a TALL one: the ogre's crown is
4.4 m up, so through the whole fight you are near enough to need the bar it is drawn off the top of the screen,
taking the gold STAGGER RIM — the one cue that says a punish is open — with it. So the bar is OVERHEAD unless
that would put it above three quarters of the screen, which is one `max` against a screen-space ceiling: far off
it rides the head as it always did, and walking in it stops climbing and hangs against the body. Dynamic with
the distance rather than a fixed height off the feet, and ONE rule for every creature — a toad never reaches it.

**THE RETICLE RIDES THE BODY, NOT A HEIGHT OFF THE FEET** (`foe.markOn`, and every creature's `lockPoint`).
Locked onto a head, the mark goes where the head goes — it dips when the head dips, hinges when the waist
hinges, and does not hang in the air over something that has ducked. Each creature names the PART its mark
rides and a point in that bone's own frame: the skull for the three humanoids, the brow for the toad, the
cephalothorax for the spiders, the cowl for a shade — and the CHEST for the ogre, whose crown is 4.4 m up and
whose head would have the camera craning at the sky (`hud.FOE_CEIL`'s problem, one layer down). The egg sac is
the one exception and it is not an oversight: one membrane on the ground has no part that moves on its own.
A bone matrix already carries the rig's scale, the facing and `pos`, and every `spawn` poses before it
returns, so there is never a frame where the matrix read is undefined. **A test pins the whole rule at once**
(`game.zig`, "THE MARK RIDES THE BODY") and it measures the mark's swing OFF THE CREATURE'S OWN AXIS, not its
height: a fixed mark still rises and falls on a hop, so a vertical check passes on the toad and the archer
whatever their reticle is bolted to. Nothing on the axis can leave it, so that number is exactly zero for a
fixed mark.

**AND A HEAD CAN GO BEHIND THE EYE.** Stood at a giant's feet its crown is above AND behind the camera, which
`projectToScreen` rightly refuses — which took the bar off screen entirely at exactly the range the ceiling
exists for. The fallback anchor is the CHEST (`centerWorld`), always in front of you, and the ceiling then puts
the bar where the head would have been.

### Stamina

- **AN EMPTY BAR LOCKS OUT roll / attack / sprint** (`STAM_LOCKOUT`). Not a violation of the
  no-time-theft law: it is the consequence of a choice made a second earlier, readable off a bar.
- **WALKING IS NEVER GATED.** Running dry caps `mv.speed` to `RUN_SPEED`, denied at the SOURCE so
  `sprintingMove` stays the one definition of a sprint.
- **RUN IT OUT AND YOU ARE WINDED** (`STAM_WIND_CLEAR` 0.5): sprint stays denied until the bar is back
  to HALF. A LATCH, not a `cur == 0` test, latched by `settleWind` from every path that moves `cur`.
  Sprint only — roll and attack keep the panic rule. The bar draws the mark (`Stamina.windedTo`).
- **YOU MAY ACT ON ANY STAMINA ABOVE ZERO** — `canAct()` is `cur > 0`, NOT `cur >= cost`. That
  asymmetry is the PANIC ROLL; gating on cost deletes the genre's most important move.
- **A COMMITTED ACTION IS NEVER CUT SHORT.** `spend` floors at 0; nothing is refunded or aborted.
- **THE REFILL PAUSES** while attacking, rolling or sprinting, then waits `STAM_DELAY`.
- **A REFUSED ACTION IS SHOWN** (`hero.stamRefused` → red ring). Under a zero-input-lag law, silence
  is indistinguishable from a dropped input. Feedback only.

### Guarding — the plain DS1 block, not ER's

- **IT IS A HELD STATE, NOT A COMMITTED ACTION.** `hero.setGuard(want)` is called every frame with the
  button's level and re-derives from scratch (`canGuard`), so an attack, roll, draught, sprint,
  stagger, death or empty bar all drop the shield with no bookkeeping. Call it AFTER `sprinting`.
- **THE SHIELD IS A DIRECTION** (`combat.GUARD_ARC`, 65° either side of facing), not a bubble — which
  is why guarding cannot answer a warband the way rolling can. A blow with a zero `fromDir` is never
  blocked, which is what lets `--shot` force reactions with synthetic hits.
- **SO A BLOW CARRIES WHERE IT CAME FROM.** Every group's update returns `?foe.Blow` (hit + attacker
  pos), not a bare `?combat.Hit`. An arrow's direction comes off its own velocity reversed.
- **IT COSTS STAMINA, NOT POISE** — `GUARD_STAM_FLAT + GUARD_STAM_PER_DMG × dmg`, refill paused while
  the shield is up.
- **CHIP GETS THROUGH AND CHIP CAN KILL** (`GUARD_NEGATE` 0.85), routed through `Vitals.hit` so death
  latches the same way. Stability is poor by design: kobold teeth ~15 of 105, the ogre's club ~45.
- **EMPTY THE BAR UNDER A BLOW AND THE GUARD BREAKS** — heavy stagger, and the shield cannot come back
  up until the pool refills. The danger is the NEXT hit.
- **`takeHit` RETURNS WHAT BECAME OF THE BLOW** (`HitOutcome`) and `game.heroTakes` is the ONE place
  that turns it into a felt beat — or a clean dodge-roll still grunts and shakes the camera.
- **HE CAN WALK A FIGHT DOWN BEHIND IT** — `hero.GUARD_SPEED` 0.75 of the walk. Capped against the
  walk, never zeroed; denied at the SOURCE in game.zig like the sprint.
- **THE STANCE LAGS, THE BLOCK NEVER DOES.** `guarding` is live on the button; `guardB` is a visual
  blend (~0.1 s). Nothing mechanical may read `guardB`.
- **THE MAN MOVES, THE SHIELD HOLDS.** Recoil goes into the BODY (sink, step back, camera, pad), only
  a little into the arm — or a caught blow looks like one that knocked the guard aside.
- **The shield is not a bone** — it rides the left wrist through `hero.shieldFit`, DERIVED from the
  stance angles (their inverse), or the first retune swings it off its own arm.

### Parrying — L2, the shield's own skill

**IT IS THE GUARD'S OPPOSITE NUMBER.** A held shield is a LEVEL that pays stamina to eat blows all day and
chips you for it; a parry is a COMMITTED WINDOW that pays `STAM_PARRY` once and refuses one blow outright.

- **L2 IS THE LEFT-HAND ARMAMENT'S SKILL SLOT** (ER's own), routed by that hand exactly as L1 is: a raised bow
  AIMS on a held level, boards PARRY on a pressed edge. It asks NOTHING about whether the guard is up —
  blocking and parrying are the two things one arm can do, not a move and its follow-up. R2 stays purely the
  heavy.
- **ON THE MOUSE THE TWO HALVES OF L2 PART COMPANY** (`PARRY_KEY`). RMB is already the guard's held level, and
  Shift+RMB — the mirror of Shift+LMB — would fire a parry every time a sprinting player pressed RMB to get his
  shield up, because Shift is the sprint here and not ER's Space. So the edge takes a key of its own.
- **THE WINDOW AND THE ANIMATION ARE TWO CLOCKS** (`parryLive` vs `PARRY_DUR`). The catch is open for ~0.16 s;
  the shove plays for a quarter of a second after it shuts, and `canGuard` refuses the whole time — so a
  mistimed parry leaves him with no shield either, whether or not he was holding one. That tail IS the price.
- **AND IT IS SLOW OFF THE MARK** (owner's call, `PARRY_OPEN` 0.10 of 0.52). Boards do not snap: a tenth of a
  second passes before anything can be caught, and the COIL is already readable in it. The startup is the
  other half of what the window costs — widening `foe.PARRY_LEAD` makes catches easier, this makes STARTING
  one a commitment, and they are separate dials on purpose.
- **THE ATTACK ALWAYS DIES; THE HEAVY STUN IS EARNED** (owner's "may heavy stun them"). `combat.PARRY_HIT` is
  STANCE and nothing else — no damage, because a parry has never been damage, and no poise, so a catch can
  never resolve as a flinch: it breaks the stance or it does not. Whether a catch is a stumble or a punish
  window is the same bar the sword has been chipping all fight, not a dice roll.
- **THE CREATURE READS THE SHIELD, IT NEVER REACHES FOR IT** (`foe.Parry`, stamped by `game.markParry` exactly
  as `markSight` stamps the eyes). Each MOVE answers for its own frames and its own reach (`ogre.parryable`):
  only the move knows where its head is, and a slam you rolled clear of is not one a shield six metres off can
  touch. **FIVE CREATURES CARRY WINDOWS** — all four of the ogre's blows (slam, swipe, return, drive — a held
  slam tell moves nothing, since the window reads the DROP), both skeletal warriors' three strokes
  (mace, slam, lunge), the brood mother's bite, the toad's leap, and the BONE KNIGHT's bash and cleave (never
  his fall — see `knight.parryable`). Adding one is a `parry` field, a `toImpact`,
  a `parryable` and its group's own `setParry`/`anyParried`: **`game.markParry` and `game.anyParried` are folded
  over `FOE_GROUPS` and keyed off `@hasDecl`**, so nothing there is edited and a group with nothing to catch just
  does not declare the pair. `parryBeat` fires ONCE a frame for the whole field — one shield, one recoil.
- **AND WHAT IS *NOT* PARRYABLE IS A DECISION, WRITTEN AT EACH `toImpact`.** A projectile is not a blow (the
  mother's spit, the slinger's clump, every arrow): there is no swing to catch, so the boards only ever block it.
  The toad's approach HOP carries no blow at all and its CHOMP is out on purpose — the leap is the committed
  thing. A BROODLING is out because a window on something that arrives out of a sac and dies to one slash is a
  mechanic nobody could read. **AND THE LEECHFLY IS OUT BY DESIGN, not by omission**: its counters are the
  ROLL (which breaks the hold) and the ranged kit (which is the only thing that reaches it perched). A window
  on the stab would make the boards the answer to a flyer, which is the one answer the creature is built to
  refuse. **HYPER ARMOUR IS NO DEFENCE** (`warrior.takeParry`): it refuses poise off the
  blade, and a parry deals neither damage nor poise — so the greatsword's uninterruptible slam is exactly the
  move the boards can still stop, which is the parry's whole reason to exist against him.
- **A WINDOW IS `foe.PARRY_LEAD` SECONDS MEASURED BACK FROM THE IMPACT FRAME** — one number, in seconds, for
  EVERY creature and every move, and it IS the difficulty. **It is 0.18** (owner: the ogre felt unparryable),
  up from 0.11, and every creature's tests BRACKET it from above: a window may never be more than a fraction
  of the tell in front of it, which is what forced the toad's `LUNGE_COIL` and the brood's `BITE_WINDUP` up
  with it. Widening the dial widens every creature at once, which is the point of there being one. You parry an instant before THE HIT (owner's call):
  what you read is the blow, not the animation in front of it, so a club, a mace, a greatsword, fangs and a
  flying toad teach one rule and not a dial learned five times. It lives in `foe.zig` for `stunCurve`'s reason —
  as a private copy per creature it is one event drifting into five numbers nobody chose. Written instead as
  fractions of each state's own clock the total was emergent and unreadable: the ogre's slam came out at 0.29 s,
  most of it while the club was still overhead and motionless.
- **SO IT SHUTS AT THE IMPACT FRAME BY CONSTRUCTION** (`toImpact` counts across the state boundary), which is
  what makes a caught blow one that never landed. A window outlasting the impact is a blow "caught" after it
  hit you; one opening earlier is a free catch on a club that has not moved.
- **IT IS A SWIPE, AND THE SWIPE COMES FROM THE WAIST** (`parrySweep` — coil, whip across, settle). A shoulder
  yaw big enough to carry the boards across his front turns their FACE with it, because `shieldFit` is the
  inverse of exactly that yaw; the TRUNK turns the arm and the boards together, so the shield stays square to
  the direction it is travelling. `PARRY_ARM_LEAD` adds a few degrees on top so the boards outrun the chest.
- **AND THE SHOVE MAY NOT BREAK THE FOLD.** `shieldFit` is also the inverse of shoulder-flex + elbow, so the
  shoulder takes `PARRY_PUNCH` and the elbow gives back exactly as much: the fold is untouched and what travels
  is the HAND. Opened at the elbow alone it swings the shield off its own arm and presents the end of his
  forearm — this is the retune `shieldFit`'s law was written for.
- **AND THE OGRE SAYS WHEN HE COMMITS** (owner: he needs more tells as to when he is about to swing). The
  ROAR at the top of a wind says a swing is COMING and then hangs there for a second and a third; the commit
  tell says NOW, once, on the wind → swing boundary itself, in all three channels the parry's own law asks
  for: `ogre_heave` out of the chest, `plantBurst` off BOTH FEET (a giant swings by planting, and dust on the
  ground is legible from every angle the club itself foreshortens to nothing in), and the shoulders driving
  over in the pose behind it. His winds are longer to match — the tell has to be readable before the beat
  that ends it means anything.
- **JUDGE IT FROM ABOVE.** A lateral arc foreshortens to nothing head-on, so the harness shoots the coil, the
  crossing and the follow-through straight down (`20o`/`20p`/`20q`). One frame cannot show a sweep.
- **A CATCH IS A BLOCK'S RECOIL PLUS SPARKS** — `noteParry` stamps `blockT`, the same channel, because the man
  moves and the shield holds either way. The sparks separate on HUE (hot amber on pale tan) and their FAN
  outruns their forward throw, or they sit superimposed on the boards they came off.
- **AND THE SWIPE ITSELF THROWS A GLINT, CAUGHT OR NOT** (`parryGlint`, owner: it needed to be far more
  apparent and to spark). It fires ONCE on the whip's own peak frame — the frame that catches — because
  under the zero-input-lag law a committed action that shows nothing is indistinguishable from a dropped
  press. **IT IS LAID ALONG THE ARC, NOT THROWN FROM A POINT** (`PARRY_GLINT_SPAN`): every burst here is
  coincident on its emission frame, which is why the CATCH is photographed four frames in — but a catch has
  an impact to justify a flash and a whiffed swipe has none, so a ball of white beside the boards with
  nothing touching them read as an artifact. Spread over the sweep's own axis it is a STREAK from the first
  frame, which is the shape the motion has. Count buys its brightness; a TIGHT fan and SHORT lives are what
  keep it a glint — thrown as far and lived as long as struck iron it was strewn across the grass a metre
  off the boards and read as litter. It is always less than a catch, and never a different colour: what
  separates the two is size, or a whiff reads as half a hit.

### The jump — A/Cross, and the one move with no ground under it

**IT IS TRAVERSAL, NOT A TECHNIQUE.** ER's own button (`hud.BTN_JUMP`, keyboard `V` — A is strafe-left, so the
letter cannot be mirrored and the jump takes a key of its own the way the parry did). It costs NO STAMINA:
only a jump ATTACK is billed in ER, and `STAM_LOCKOUT` exists to punish greed in a fight rather than to fence a
man off the map. There is no jump attack and no fall damage yet.

- **`pos.y` IS STILL THE GROUND UNDER HIM** — `game.groundActor` remains its only writer, and `hero.lift` is
  what he is flying above it by. The leechfly's law exactly, with one addition it needed: the height actually
  integrated is `airY`, the WORLD height of his feet, and `lift` is DERIVED off it (`airY − pos.y`) every
  frame. That is what makes running off a ledge work — the datum falls away underneath and the gap opens on
  its own, where a lift integrated over a moving datum sinks with the ground it was measured from.
  **`lift` is ZERO unless he is airborne**, so a teleport (respawn, F5, the shot harness) can never strand him
  standing on nothing.
- **TWO NUMBERS ARE THE DECISION AND THE OTHER TWO ARE SOLVED** — `JUMP_APEX` (1.0 m) and `JUMP_AIR` (0.72 s);
  `JUMP_G` and `JUMP_V0` fall out of them. An apex and a gravity authored side by side are two dials for one
  shape and they drift. The apex clears THREE terrain risers where a walk gets two (`env.STEP_UP`), which is
  what makes a sculpted ledge something a player answers with a button instead of a detour — and a test in
  `game.zig` pins it against `wf.HEIGHT_STEP` from both sides.
- **THE INTEGRATOR IS THE CLOSED FORM, not `v -= g·dt; y += v·dt`.** That plain pair loses `g·t·dt/2` of
  height: NINE CENTIMETRES of apex at 30 fps and none at 240, which is `env.walkStep`'s bug wearing a
  different hat. The half-a-`dt²` term makes it exact at every frame rate, and a test flies all four.
- **GRAVITY LIVES IN `tickClocks`**, with the other clocks and for their reason plus one of its own: a blow
  mid-air routes him to `updateStun` and a death to `updateDeath`, and a man who stopped falling because he
  got hit would hang in the sky. `dropActions` deliberately does NOT clear `jumping`. It IS gated on `held`,
  though — the pause card still calls `update` for the breathing bob.
- **IT IS `committed()`, beside the roll.** One predicate, and every rule then lands without a second list: no
  double jump, no roll or cast out of the air, a sprint that stops when his feet do, and an attack pressed
  mid-flight BUFFERED into the one slot and fired the frame he lands (`tickAir` → `fireQueued`).
- **THE STICK BENDS THE ARC AND MAY NEVER RE-PRICE IT** (`AIR_TURN_RATE`, well under `TURN_RATE`). Heading and
  ground speed are committed at takeoff, ER-style: a standing jump goes straight up and a sprint jump carries
  the sprint. Steering the speed instead would make a standing hop a free sprint with no bill.
- **HE MAY FLY OVER ANYTHING HE IS ABOVE, AND NOTHING ELSE** (`env.flyStep`, beside `walkStep` because
  traversal is decided in one file). A man in the air asks a different question of the terrain — not "may I
  climb this" but "am I over it" — so his own FEET replace the riser rule. Without it a hop at a cliff carries
  him into its footprint, `groundActor` lifts him up three metres of it, and the ledge nobody could walk up has
  been climbed by pressing A at it. **Plus the walk's own `STEP_UP` allowance**, since on the takeoff frame his
  feet are still on the ground he left: a jump may never travel WORSE than a step. **THE SAME RULE RUNS ON ALL
  THREE THINGS THAT CAN BE IN THE WAY, each off its own top**: on BODIES in `collideActors` (he clears a toad
  and is stopped dead by an ogre, off the creature's `topWorld`) and on the world's SOLIDS in
  `env.resolveActor`, which takes his `footY` and skips any collider whose `Solid.h` is under it. That last one
  was the report — *jumping did not let you clear low obstacles* — and it was the odd one out rather than a
  missing rule: `buildSolids` has always stamped each collider's blocking height off its `part.h`, and
  `blocksPoint` (an arrow lobbed over a kerb) and `blocksSight` (a look passing over one) have always read it.
  The PUSH-OUT was the one consumer that did not, so no altitude cleared anything and a man at the top of his
  arc was shouldered off a fallen log. **A wall is still a wall at any altitude** — that law is about a WALL
  and it holds by construction, since a wall's `h` is 3 m and `JUMP_APEX` is 1.0; what changed is that
  knee-high rubble stopped being one. **And NO `STEP_UP` allowance there**, unlike `flyStep`: the terrain's
  riser rule already lets a WALK take 0.55 m so matching it costs nothing on foot, but there is no
  step-over-props rule to stay level with, and an allowance would let a man standing still walk through low
  rubble. Feet genuinely above the top, or it is in the way. **The FOES are deliberately still measured at
  `pos.y`**, flying or not: nothing but the hero has a real integrated height yet (a hop's arc is scripted,
  the fly's `hover` is a field), and handing the real one over would sail a leechfly at 4.6 m through
  architecture. When a creature's flight becomes an integration, that is the one line that changes.
- **THE LENS TAKES ONLY A SHARE OF IT** (`camera.LIFT_SHARE`, 0.55, eased). The rig is bolted to his shoulder,
  so a target that rose the full metre would hold him dead still in frame and move the WORLD instead — the
  same picture with the wrong subject. `hero.shoulderPoint` is therefore over the GROUND under him and how
  much of a jump the camera takes is the camera's decision, made once, in `camera.zig`.
- **THE POSE IS THREE TERMS OFF ONE NUMBER — the vertical velocity.** DRIVE on the way up (the leg that pushed
  still extended behind, ankle pointed, arms thrown up), TUCK where the velocity passes through ZERO — which
  IS the apex, so the pose cannot drift out of step with the arc the way a second clock would — and REACH on
  the way down, legs under him and toes up to receive. **The arms must survive the apex** (`JUMP_ARM_HOLD`):
  drive and reach both pass through zero there, so an arm hung off either alone goes limp on the one frame the
  whole jump is read from. NO ROOT PITCH — `rx` at the root rotates about the world origin and swings the
  legs; the whole fold is spine and chest, and a test pins the trunk under 20° off upright for the whole arc.
- **THE ABSORB IS VISUAL ONLY, and that is a law.** A landing recovery that took the stick off him would be
  the hitstop the house rules refuse, paid on the most ordinary move in the game. It is a term in poseBody's
  own CROUCH (a caught blow's sink is the other), so he lands into a walk, a sprint or a standstill without
  three copies of a stance — and it OVERSHOOTS its rest and settles back onto it, through the shared `absorb`
  curve the parry's shove already used.
- **THE BEAT GOES ON THE LANDING, NEVER THE TAKEOFF** — nothing has happened until the ground stops him.
  `landed` is a one-frame flag (`loosed`'s rule) carrying `sfx.land` + the ground overlay, `rumble.land` (mostly
  LOW, where mass lives, against the roll's high) and `SHAKE_LAND`, which sits over a bolt leaving and under
  the lightest blow he lands. The takeoff gets a voice and nothing else. **And no footfalls in mid-air**: the
  gait phase keeps running so he lands back into the stride he left with.

### In combat, and the quick bar

**THERE IS ONE FLAG THAT SAYS A FIGHT IS ON** (`game.inCombat`), and nothing about the HERO is in it: swinging
at air in an empty field is not combat and standing still in front of a roused ogre is. A creature counts if
its `foe.Leash` is ROUSED — it has been hit, or it is coming for him wherever he stands — or if he is inside
the range it notices him at, **and that range is the group's own `FoeGroup.aggro`**, never a radius invented
for this: a toad's world is 11 m and an archer's is 24, and one flat figure is wrong at both ends. Sight is
deliberately not asked; it is a real question (`env.sees`) but it flickers as he rounds a corner, and a state
that decides whether a menu works may not blink. A CORPSE DOES NOT COUNT (`foe.corporeal`) — a fight is over
when the thing swinging at you stops, not when its motes have finished going up. **…and a BOSS ZONE, the day
one exists**: `worldfmt` has no boss record yet, and when it does its region test is the third term in that
one function and nothing else changes. `foeFights` is the per-creature term, split out so the rule has a test.

**IN COMBAT A CONSUMABLE COMES OFF THE QUICK BAR OR IT DOES NOT COME AT ALL** (owner's rule). The character
book's inventory Use is refused while a fight is on and the panel says where to go instead; out of combat that
page is the convenient way and the bar may sit empty. What is on the bar is therefore a decision made BEFORE
the fight, which is the whole point of it.

- **THE BAR IS THE CROSS'S DOWN SLOT** (`combat.Quick`, ten entries — ER's pouch). It is not a second system
  beside the flask: **the two flasks are simply its first two entries**, so a fresh game plays exactly as it
  did. `Flasks` still owns their CHARGES, because those come back at a bonfire where everything else comes out
  of the bag — `combat.quickCount` is that split, ONE copy, asked by the HUD off the live game and by the
  book off its `View`.
- **CYCLE STAMPS `flasks.sel`, it does not cycle it** (`hero.cycleQuick` → `syncFlask`). The draught, the HUD
  tint and the charge count all keep reading the one field they always read, and only the bar decides what
  is up. `Flasks` has no `cycle` of its own — `Quick.cycle` is the only one, and `sel` is only ever STAMPED.
- **A REMOVAL LEAVES ITS HOLE.** The bar is stepped by muscle memory mid-fight; a list that compacts under
  you every time you drop something is one you cannot learn.
- **EACH BAR ENTRY IS ITS OWN SOCKET ON THE PAGE** — two rows of five on the paper doll, and Confirm on one
  puts a kind in THAT socket (`combat.Quick.put`, which moves a kind already elsewhere on the bar rather
  than copying it). The rows are FILTERED to what he actually carries (`quickOffered`) and carry an empty
  row, so a kind's ordinal is not its row and `pickIndexOf` counts it out the way `candidates` builds it.

### Souls — the drop, and the ring that refuses it

**WHAT YOU WERE CARRYING IS ON THE GROUND WHERE YOU DIED** (`souls.zig`) — DS's bloodstain and ER's rune drop (this game calls the currency SOULS throughout),
which are one mechanic under two names. Everything comes off him on the frame he DIES rather than at the
respawn, so the spill plays under the YOU DIED card, which is the one moment nothing else is playing.

- **THERE IS EXACTLY ONE.** A second death overwrites the first and the first is gone for good. That is not a
  storage decision, it is THE mechanic: a list of drops would quietly delete the whole risk.
- **NOTHING ELSE SPENDS IT.** No timer, no decay, no despawn on distance — only picking it up or dying again.
  A death RE-HOMES the field (`game.resetFoes`) and must not touch the drop; only a change of MAP clears it,
  which is `game.armScript` and nowhere else.
- **AND RETRIEVAL IS INSTANT** (owner's call). No committed action and no animation on the man: the souls are
  on the counter the frame he presses. The animation is all on the DROP — motes solved to ARRIVE at his chest
  inside their own life (the wand gather's construction with the ends swapped), so it reads as a thing being
  taken up rather than a thing being scattered.
- **IT IS A TREE, NOT A FLAME**, so it obeys the dead-limb law: a crooked bole in three leaning segments,
  limbs that rise to an elbow, droop off their own line and stop in a BLUNT swelling. It grows out of the
  earth over `RISE`, overshoots its own height and settles onto it (the reactions law, on a prop).
- **ONE EMISSIVE LEVEL, THREE ALBEDOS.** Vertex alpha is the emissive channel, so all three golds sit at one
  alpha and separate on hue and value alone — at two levels the shaft bands where the level changes. The
  albedos are SOLVED off a sampled render (`souls.EMISSIVE`): the first pass authored the tips at 246,220,150
  and they came back 255,255,221, a white knuckle, which is why it read as BONE and not as gold.
- **IT SAYS WHERE IT IS OUT LOUD** — `souls_hum` on a RETRIGGER (`HUM_EVERY`, the leechfly's whine rule), cut
  short enough that consecutive takes overlap. It is what lets you find one you walked past.
- **THE PROMPT IS FIRST IN `game.reachable`**, ahead of the fire, the folk and a box: you can die at a bonfire,
  and on the frame you walk back in there is exactly one thing you came for. One press clears it and the fire
  is offered again. Its ring is the GENEROUS one — `souls.REACH` 2.6 against a box's 2.1, asserted at comptime
  in `souls.zig` — because you come back for this under pressure and fumbling the reach is not the tension.

**AND THE SOUL BINDING RING REFUSES THE WHOLE THING** (`item.soul_binding_ring`, DS's Ring of Sacrifice).
Carried, a death takes the RING instead of the souls: it snaps, he keeps the lot, and nothing is left standing.

- **CARRYING IT IS ENOUGH.** There is no ring slot and there is no equip system, so the bag is the wearing.
- **IT IS NOT A TOOL.** `usable` is false and it is off the quick bar: a Confirm on it would promise something
  the mechanic never does. It is the one thing in the bag spent by DYING.
- **ASKED OF THE ITEM, NOT THE KIND** (`item.bindsSouls`, `isFlask`'s shape) — a second binding charm is one
  row in `item.zig` and no edit at the death site.
- **ONE IN THE WORLD**, in a chest, and a test pins that. A box that refilled with them is a death you never
  have to take.

### Status effects — POISON, and the shape every one after it takes

**ONE METER DOES ALL THREE JOBS** (`combat.Status`, owner's call). Hits fill it; full, it **PROCS**; and the
same meter then becomes the **CLOCK**, draining over the effect's life while it bills HP. **It cannot be
topped up while it drains** — poison is a state you are already in, where a BURST status (bleed) resets to
nothing and re-procs at once. That is why there is no second clock: what the bar shows is always the same
number, so a readout and a mechanic cannot disagree.

- **DECAY IS WHAT MAKES IT PRESSURE** (ER's own): the meter falls once you STOP taking doses
  (`POISON_DECAY_DELAY` then `POISON_DECAY`), so spaced hits never proc and LINGERING is the whole cost.
- **A SOURCE HANDS OVER BUILDUP, NEVER HP.** What the poison takes is the proc's business, not the cloud's —
  so a source keeps no clock of its own and cannot fall out of step with the decay.
- **THE PROC IS BILLED AS A DRIP** (`Vitals.drip`): it carries no poise, and stamped through `hit` it would
  deny him a whole poise bar it has no business touching. It takes `POISON_HP_FRAC` of MAX HP over its span,
  a fraction so it is worth the same on a Vitality build as on a fresh sheet.
- **THE DRAIN IS SILENT AND UNFLASHED.** The red edge and the beat belong to a BLOW; a status running
  fourteen seconds cannot own the frame, and a flash re-armed every tick would never go out. **The PROC gets
  the whole of the feedback, once** — one shake, one voice, one flash. The bar is the cue for the rest.
- **THE BAR HAS TWO FACES OFF ONE NUMBER** — violet FILLING (a threat), toxic YELLOW once it has gone off (a
  thing happening to you), and it draws **nothing at all** while empty. Not green: it sits directly under the
  stamina bar and the two measured as the same bar.
- **A BONFIRE CURES IT** (`hero.makeWhole`), and a death is a return to one.
- **TWO SOURCES, ONE FLUID** — the sporeling's spore cloud (`SPORE_BUILD`) and the brood mother's spit
  (`M_SPIT_BUILD`) and acid pools (`ACID_BUILD`). Neither floor deals damage any more; both are pressure.
  Standing in spores and acid at once doses as **both**, which is why they are two `add` calls and not a max.
- **THE HERO ALONE CARRIES ONE.** Nothing applies a status to a foe, so nothing on a foe reads one.

### Resistances — PoE2's four

- **PHYSICAL IS NOT ONE OF THE FOUR.** `Elem` is fire/cold/lightning/chaos. What mitigates physical is
  ARMOUR, which does not exist yet. Do not add a "physical resistance" — the day armour lands it is
  its own curve `A/(A + 5*dmg)`.
- **75 IS THE CAP, NEGATIVE AMPLIFIES** (`RES_CAP` 75, `RES_FLOOR` −100). Stored uncapped, capped on
  READ (`Resists.at` vs `.raw`).
- **A SPREAD IS WRITTEN BY NAME** — `combat.resists(.{ .fire = -45 })`, matched at comptime so a
  rename is a compile error. An array literal in enum order silently shifts on a fifth element.
- **POISE AND STANCE BELONG TO THE BLOW, NOT THE BODY.** `guardChip` is damage only for the same
  reason. **A shield is billed on the RAW blow** (`Hit.raw`).
- **THREE AND A HALF OF THE FOUR ARE LIVE** — FIRE (hero's fire arrow, the tallowed sword, kobold sling
  clump), LIGHTNING (the thundercrock's alone — nothing deals it AT the hero), CHAOS, which is the WAND'S
  ALONE (the bolt and the roots' grip), and now **COLD, which is the NECROMANCER'S ALONE**: its rune ring is
  the only thing in the world that deals it, and it deals nothing else (`necro.FROST_HIT` carries no
  physical, which a comptime assert pins). Nothing in the world deals chaos AT the hero since the brood's
  venom and the sporeling's spores became POISON, so cold is now the only element he actually meets.
- Every foe carries its own table, authored where its HP is (`initFoe(..).withRes(..)`):

  | creature | fire | cold | lightning | chaos | why |
  | --- | --- | --- | --- | --- | --- |
  | gaping toad | +40 | −30 | −25 | 0 | wet out of a bog, cold-blooded |
  | skeletal archer | −35 | +60 | 0 | +45 | dry bone burns; no flesh to freeze or poison |
  | one-eyed ogre | +30 | +30 | −15 | +20 | too much mass, but stands in an open field |
  | kobold (all three) | −45 | +20 | 0 | 0 | fur goes up — the fire arrow IS the answer to a warband |
  | brood mother / broodling | −25 | +35 | 0 | +75 | chitin and its own acid |
  | egg sac | −70 | 0 | 0 | +75 | dry silk over a membrane |
  | skeletal warrior | −35 | +60 | 0 | +45 | the archer's own table — it is the archer's body |
  | shade | +30 | +65 | 0 | −45 | nothing there to burn, and cold is what it already is |
  | leechfly | −55 | −25 | 0 | +35 | a wing is a membrane; the chaos in it is what it has been drinking |
  | the Rooted | −70 | +40 | −20 | +30 | dead dry wood; fire is the counter, lightning splits it |
  | sporeling | −50 | +15 | 0 | +75 | a damp little fungus stuffed with its own element |
  | Bone Knight | −35 | +60 | 0 | +45 | the archer's own table again — it is the archer's body in a suit |
  | Delver | +20 | −30 | −40 | 0 | packed earth over a damp hide; a bolt EARTHS through the one thing that is part of the ground |
  | Necromancer | −35 | **+75** | 0 | +45 | the archer's table with COLD taken to the cap — it is the one thing in the world that deals cold, and a creature you could freeze with its own element is one whose identity the sheet argues against |

- **NOTHING GRANTS THE HERO ANY YET, AND THE SHEET SAYS SO** — the book's STATS page shows all four at
  0%. `makeWhole` CARRIES RESISTANCES ACROSS a bonfire: they are what he is, not a meter to refill.

### The character sheet (`stats.zig`)

Seven attributes; `hpFor`/`fpFor`/`staminaFor` turn Vitality/Mind/Endurance into the bars at ER's
documented soft caps. **The starting sheet reproduces the tuned bars exactly** — every attribute
starts at 15, which is where the curves yield 70 HP / 60 FP / 105 stamina, so `hero.HP_MAX`,
`combat.FP_MAX` and `combat.STAM_MAX` are DERIVED and a test pins all three. **The bars take their
size from the sheet in one place** — `hero.makeWhole`. The four attributes nothing reads yet say so on
their own row.

### The passive tree (`passivetree.zig`) — PoE2's, radially

**YOU START IN THE MIDDLE AND THREE ARMS RUN OUT OF IT.** The arms are never NAMED on screen — colour and
direction carry which is which (`Arm.ink` is all that is left of them). Nothing here is a class: all three
hang off the hub, so all three are open from the first souls you spend.

- **YOU CLIMB, AND THE LINK IS THE RULE** (`feeders` / `Tree.reached`). A node opens the moment ANY ONE of
  the things it hangs off is yours — no counts, no tolls, just a path walked a node at a time to the capstone
  you want. `feeders` is asked by the DRAW and by `locked` alike, so the page cannot gate a branch on
  something it does not show. **The capstone is the one node with two ways in**: both strands of an arm climb
  to it, and a tip only one of them reached would make the other a dead end nobody walks.
- **IT RETURNS A SLICE, NOT A PAIR OF OPTIONALS.** As `[2]?usize` a one-feeder node carried a trailing null,
  every reader read that null as "hangs off the hub", and the whole tree opened at once with a second link
  drawn from the middle to every node on it. An EMPTY slice is the hub and nothing else is.
- **TAKING A NODE IS THE LEVEL** (owner's call) — one press spends the souls and puts the node on the board.
  There is no point pool between the two: a point in hand is a decision already paid for and not yet made,
  which is a state with nothing to show for itself. `Tree.take` hands back what it charged rather than
  reaching for the counter (`souls.take`'s shape), so `game.bonfirePick` is the one line that can bill him, and
  it is the ONLY thing in the game that spends souls.
- **SOULS, NEVER RUNES**, in the code as well as on the page. The currency is `combat.Souls`, the counter is
  `hero.souls`, and the one ITEM with "rune" in its name (`rune_arc`) is a physical object and not the
  currency. `nameless_soul` is the item that IS worth souls, and it is named for what it pays out.
- **THE PRICE IS MEASURED AGAINST A BODY.** A toad is 60, an archer 130, a mother 240 — so `costAt` is set
  where the first node is three archers and the whole one-and-twenty is a game's worth of killing (~80k). It
  is ONE price per level whichever node it lands on: what you buy is the level, and which node is the choice.
- **SPENT AT A BONFIRE, READ ANYWHERE.** The book's fourth page is the wheel READ-ONLY — where a build is
  planned. The fire's own screen is where it is committed. `passivetree.drawPage` is ONE copy drawn by both,
  `spendable` being the only difference.
- **THE BONFIRE IS A SCREEN, NOT A PAUSE** (owner's layout). He sits in the RIGHT of the frame and the fire's
  menu is a list down the LEFT: **Level Up** (which opens the wheel) and **Leave Bonfire**, and nothing else
  yet. The wheel is shown ONLY once Level Up is chosen — a tree behind every sit buries what a bonfire is.
- **GETTING UP IS A ROW ON THAT LIST, OR BACK.** It was "any button", which cannot coexist with a cursor: every
  press that chose a row also stood him up. Back is the one button that can never also pick, so it is the one
  exception (owner's call) — off the wheel first, then out of the fire. The character book and the pause card
  are still BOTH refused at a fire.
- **NO HINT ROW ON THE FIRE'S LIST** (owner's call). Four verbs, each saying what it does; a crib under them was
  spelling out which button picks a row. The WHEEL keeps its hints — LS/RS/zoom is not guessable.
- **THE VIEW IS PANNED, NOT SHEARED** (`game.restCamera`, `REST_PAN`). Eye and target move by the same vector
  along the camera's own right axis; swinging the target alone turns the camera and re-composes the shot
  instead of sliding it. Screen-right is `cross(forward, up)` — `camera.rightXZ`'s law, one layer up.
- **THE LEFT STICK WALKS THE WHEEL, THE CROSS ZOOMS IT AND THE RIGHT STICK PANS** (`menu.stickPush`,
  `menu.dpadZoom`, `menu.stickPan`). The zoom is on the CROSS and not the bumpers, because the bumpers are the
  character book's page turn and the wheel is one of its pages — a zoom that took them would strand you on the
  wheel with no way to turn off it. Which is also why the cross is then WITHHELD from the walk on a wheel and
  kept on a list: `menu.navFor` is that decision, in one place, read by both wheel screens. A
  stick is a LEVEL where a walk wants EDGES, and reading it naively is a known genre of bug (Godot #54959 is
  the same one). FOUR STANDARD PIECES, all of them here: a RADIAL magnitude, never per-axis — the square's
  corner passes at 0.62 on each axis while the true deflection is 0.88, so a lazy diagonal reads as a hard
  push; a SCHMITT TRIGGER (`STICK_FIRE` to arm, `STICK_REARM` to re-arm), because one threshold chatters
  across itself; DAS then ARR, the falling-block idiom, so a nudge is exactly one step and a hold is a
  readable crawl; and a DEAD CONE AT THE DIAGONALS — **ON A LIST OR A GRID, WHICH IS THE ONLY PLACE IT
  BELONGS.**
- **A RADIAL LAYOUT TAKES THE THUMB'S OWN BEARING, NEVER ONE OF FOUR** (`menu.stickPush`'s `radial`, owner:
  walking the tree with the stick "feels horrible"). The three arms run out at 0, 120 and 240 degrees, so almost
  nothing on this page lies along a screen axis: from the middle the ring-0 nodes sit at ∓15, 105, 135, 225 and
  255 degrees, and every outward step along the two lower arms runs down a bearing near 96 or 216. Snapped to
  four axes and then gated by the 32-degree dead cone, the natural push — the thumb pointed AT the node — landed
  IN the cone and did nothing, on two arms out of three; what worked was pushing LEFT to reach the arm drawn
  down-and-RIGHT. So `passivetree.step` takes a HEADING (`dx`/`dy` as floats, normalised inside it) and its own
  wedge does the choosing: point at a node, go to that node. The CROSS and the KEYS still hand it a cardinal —
  those devices have four directions and that is all they have — and a LIST still takes the sign of an axis
  (`mathx.signI`). Two tests pin it: a push aimed at any ring-0 node from the middle reaches THAT node, a push
  aimed down any link `feeders` draws reaches what it feeds, and a rough shove within 20 degrees of an arm finds
  that arm's near end. **AND A WHEEL IS STEERED, NOT RE-PRESSED**: on a list a direction rolled into without
  returning to centre costs a full DAS, because a thumb going round the rim crosses all four quadrants; on a
  wheel that IS how you cross the layout, so a turn past `AIM_TURN` (40 degrees) fires at once and a drift under
  it carries the repeat onto the bearing the thumb is on NOW.
- **THE FRAMING IS A SQUARE ON THE HUB, NOT A FIT OF THE BOUNDING BOX** (`passivetree.VIEW_R`, owner: "square
  with central node in center, so it starts pannable, not bottom heavy"). Three arms at 120° have a bounding box
  whose centre is nowhere near the hub — the wizard's spoke runs four rings straight UP where the two lower ones
  reach two rings down — so a box-fitted framing opened with the one spot the whole page is described from a long
  way below the middle of the panel and the slack piled at the top. A wheel's own symmetry is its RADIUS: the
  square is centred on the hub, `unit` comes off the panel's SHORT axis so it fits either way up, and `VIEW_R` is
  the outer radius of what is actually DRAWN — the keystone's centre at `RINGS`, its disc, and the breathing halo
  an OPEN one wears. A test pins the hub to the centre of the box at three aspect ratios and pins `VIEW_R`
  against every node's own reach. **AND THE PAN IS LIVE AT `ZOOM_MIN`** (`PAN_FLOOR`): it used to be pinned to
  nothing there on the argument that a box-fitted wheel has nothing off-screen, which stopped being true the
  moment the framing became a square on the hub.
  **THE ARMS ARE NEVER CAPTIONED, so nothing reserves room for one.** `CAP_OUT`/`CAP_HALF`/`onAxis` outlived the
  labels the "never NAMED on screen" rule deleted and went on reserving 5.35 units above the hub against 2.83
  below — dead air the fit then paid for by drawing every node ~19% smaller. That is what "bottom heavy" was.
- **The zoom re-centres on the CURSOR** as it goes in (blended from the hub, so nothing moves at `ZOOM_MIN`);
  scaled about the hub the whole way instead, the first notch pushes what you
  were reading off the panel. The zoom is read as a HELD LEVEL so it glides rather than notching, and the pad's
  half of it is the cross alone — a desk has the mouse wheel and needs neither.
- **THE MIDDLE IS A PLACE THE CURSOR MAY REST** (`passivetree.HUB`, indexed one past the last node so every
  `NODES[i]` site is untouched). It is where the wheel opens, it takes no press and it is never a purchase -
  the reading column describes the TREE from it. A cursor that cannot sit on the one spot the whole thing is
  described from is a cursor with a hole in it.
- **THE TREE OWNS THE LEVEL, NOT THE SHEET.** `stats.Sheet.level` counts points past the start, and a node
  spent on a PASSIVE moves no attribute — it would report a lower number than the fire charged for. So level
  is COUNTED off the board (`spent() + 1`) and every attribute past the starting sheet came off a node
  (`Bonus.sheet`). There is no attribute allocation beside this and the STATS page is read-only for good.
- **ONE GRANT PER NODE.** A node that did two things could never be named on the row that names it, and the
  page is read at a glance.
- **THE REST OF THE GAME READS FIELDS OFF ONE `Bonus`**, stamped on the hero by `game.applyTree` →
  `hero.applyPerks` (sheet + resistances + perks in ONE call, or a bar is sized off the sheet he had a node
  ago). Nothing outside `passivetree.zig` walks the node list. Five hero-local sites read it: the roll's stamina,
  the roll's i-frames, the cast's cost, the cast's blow (`Hit.scaled` — the WHOLE blow, or a boosted sorcery
  staggers exactly as hard as it did at level one) and the guard's negation (`combat.guardChip` takes the
  figure as an argument now; a foe's boards pass the flat `GUARD_NEGATE`).
- **`foe.PARRY_LEAD` IS DELIBERATELY NOT A PERK.** It is one difficulty dial every creature's tests bracket
  from above at comptime; a node that widened it would move eleven creatures at once, which is the opposite
  of what one number in `foe.zig` exists for.
- **THE WALK IS GEOMETRIC** (`book.slotStep`'s law) — on a wheel an ordinal walk steps between nodes nowhere
  near each other. A test floods all four directions from every node: nothing the cursor cannot reach.
- **THE THREE STATES SEPARATE ON FILL, NOT ON HUE** — taken is solid, open is a lit rim over the seat, locked
  is the rim gone to nothing. The arm's colour is already carrying the arm; a hue shift for state is one
  state read at arm's length.
- **ONE LINK PER NODE, AND TWO ONLY AT THE CAPSTONE.** The first pass wired the hub to six nodes and drew a
  web dense enough to have to read past; a later one cut every link for a bare spine, which meant the page
  showed nothing about what connects to what. The link IS the rule now, so it can be neither.
- **THE SELECTION IS BUILT OUT OF THE NODE** and drawn last, by the wheel itself so both screens get it: a
  breathing halo standing off the disc, a hard rim on it, and the chrome's corner brackets round that. All
  three — the rim alone is lost in a taken node's fill and the halo alone in the ring circles behind it.

## Armaments

**R1/R2 (and L1/L2) BELONG TO THE ARM, NOT THE WEAPON.** The attack buttons are read as buttons and
routed by which armament is in that hand, so neither weapon can swallow the other's press. L1 is the left
hand's ACTION (block / cast) and L2 is its SKILL (aim / parry), each split by what that hand is holding. Swaps:
D-pad Right / Q = sword ↔ bow; D-pad Left / F = shield ↔ wand; D-pad Up / G = bolt ↔ roots. The QUIVER keeps
keyboard Y alone — the cross is four directions and the spell has taken Up, so on the pad the arrow is changed
in the character book's ammo slot.

**A SELECTED VARIANT IS LATCHED WHERE THE COMMITTED ACTION STARTS**, and the selector REFUSES while one
is running — what starts is what lands, and a swap cannot reach back into something already in flight.
**One place answers what it costs** (`combat.spellFp`), or the HUD's "could he?" and the action itself
disagree. Exhaustive switches over the selection, so a new one is a compile error until it has said what
it costs and what it does.

### The bow (`hero.zig`)

- **THE SHIELD GOING IS ANATOMY, NOT A BALANCE DIAL** — one hand cannot haul a string and hold boards,
  so it is `canGuard` ASKING the arm rather than the swap clearing a flag. The HUD's LEFT slot goes
  EMPTY, which is exactly what a raised bow costs.
- **IT IS THE SKELETONS' BOW** — `archer.bowMesh`/`stringMesh`/`nockArrowMesh`/`poseBow` are shared and
  every stance angle is lifted from `archer.poseUpper`. This is the one import running against the
  grain (hero → archer) and the reason is written at it.
- **THE AIM IS HELD, THE LOOSE IS THE ONLY COMMITTED PART** — `setAim` re-derives from `canAim` every
  frame; the one committed action it allows is `shooting`.
- **AIMING SUSPENDS THE LOCK OUTRIGHT** (`game.activeLock`) — the stick is doing the pointing.
  Suspended, not dropped. R3 is dead while the bow is up. **And it slows the look**
  (`game.AIM_LOOK_SCALE`): the mark is thirty metres out.
- **A BOW CHIPS; IT DOES NOT WIN.** Both shots come in under the melee they compare to and the poise
  is slighter still. Behind a raised bow he moves at `BOW_AIM_SPEED` (0.45 of the walk, under the
  shield's 0.75): a shield is something you walk behind, an aim is something you stand still for.
- **ARROWS ARE FINITE** — `combat.Quiver`, ten plain and five fire (`FIRE_ARROWS_MAX`), refilled at a
  bonfire. The quiver is checked BEFORE stamina is charged. The SELECTED kind is what flies, empty or
  not, and the kind is LATCHED at `startShot`.
- **THE FIRE ARROW** hangs fire worth `FIRE_ARROW_FRAC` (0.5) of the shaft's physical ON TOP of it —
  PoE2's "adds X fire damage", physical untouched. It uses `.flame` and `propart`'s fire palette; a
  second kind of fire in one world reads as a different substance. Tongues, not a blob.
- **THE SHOT CONVERGES ON THE RETICLE, it does not run parallel to it.** Thrown at a point ON the
  camera's centre ray at the distance that ray REACHES (`camera.centreRay` → `game.camAimPoint`).
  Aimed along the camera's forward from the nock instead, every shot runs offset by however far the
  bow is from the eye. Loft is only added when the target is a real point.
- **THE AIM PUSHES THE EYE IN PAST HIM AND FADES HIM OUT** — the player's own `dist` is never written,
  and the fade is LIT-PASS ONLY with the depth mask off.
- **HIS SHAFTS ARE A PIERCING BLADE** (`foe.Blade.pierce`), through each creature's own `tryHit`. It
  neither reads nor writes the swing latch — both halves matter.

### The wand (`hero.zig`) — the first thing that spends FP

- **A CAST IS COMMITTED, NOT HELD** — the FP is gone the moment it starts, so it lives in `committed()`
  beside the swing and the loose, is not buffered, and a stagger drops it with the charge spent. He is
  PLANTED for it.
- **BILLED IN FP AND NOTHING ELSE** — `BOLT_FP` 12 of 60, five casts to a bonfire. An empty stamina bar
  still leaves him a spell; the wand competes with the flask, not with the roll.
- **PAY OR CAST NOTHING** (`Focus.spend`) — deliberately the INVERSE of stamina's panic rule: a
  half-paid spell would be a spell that half exists. `hero.fpRefused` → `hud.refuseRing`.
- **THE ARM GOES OVERHEAD AND SWEEPS ACROSS THE TOP**, and repeated casts sweep OPPOSITE ways
  (`castAlt`, flipped at the START of each cast). `rz` swings the left arm through the frontal plane
  and 180 is straight up, so raise and stroke are ONE channel: overhead ± `CAST_SWEEP` (34).
  `CAST_SH_FWD` (36) tips the plane forward so the stroke passes in FRONT of the head.
- **THE ARM GOES LONG AT THE THROW** (the warriors' law) — a folded elbow keeps the stone inside his
  own silhouette however far the numbers say it reaches.
- **THE ROD IS NOT A BONE** and has NO fit matrix: authored in the left wrist's frame along −Y.
  `wandTipWorld` is MEASURED off the mesh's constants (the ogre's `clubLowWorld` law).
- **THE BOLT FLIES THROUGH THE ARROW POOL** (`archer.Shot.bolt`) — cover, gravity, ground, expiry and
  the swept `pierce` test are one body of code.
- **ALL CHAOS, NO PHYSICAL** — `BOLT_HIT` 24 chaos, poise 14, stance 6. Chaos is the most-resisted
  column in the game, so the wand answers toads and kobolds and is near useless against skeletons.
  An honest trade, not an oversight.
- **ONE VIOLET FOR THE WHOLE SPELL** — stone, gather, both bursts, the streak and the LIGHT. Two substances
  of one element is what the brood's rule forbids.
- **THE STONE IS THE ONLY LIGHT IN THE GAME THAT MOVES** (`hero.wandLight`) — an ember on the carry, a swell
  through the raise, a flare on the throw. `env.uploadLights` takes it as a RESERVED slot, so the world's
  own lights fight over one fewer and a brazier he is standing beside can never evict his own spell. Point
  light is MULTIPLIED by albedo here, so the pool reads loud on marble and muted on grass — that is the
  engine's rule and every torch obeys it.
- **THE GATHER RIDES THE HAND AND ITS LIFE IS WHAT PAYS FOR IT.** Motes are solved to ARRIVE at the stone,
  and the stone crosses a metre and a half through the lift: solved against where it is now they converge on
  where it WAS. Adding the tip's own velocity fixes the constant part; the leftover is ½·a·life², so the
  correction that matters is a SHORT LIFE, and `drawParticles` fades radius with alpha, so a short life has
  to be bought back with RADIUS, never with more motes.
- **THE RELEASE IS A CONE, A COLLAR AND ONE FLASH.** The cone alone is indistinguishable from the bolt's own
  first metre; what says the stone LET GO is the collar, thrown sideways out of the bolt line. The flash is
  a SOLID sphere, not additive — at twice the head it was a translucent balloon hiding the rod, the stone and
  every spark on the busiest frame in the spell.
- **THE CHARGE RISES IN THE GRIP, AND A `rumble.Event` CANNOT RISE** — a `Motor` decays from its peak. So the
  raise is pulsed every frame with a peak scaled by `hero.chargeFill` (`rumble.castCharge`), which is 0 past
  the throw so it stops of its own accord. The release is a crack (`cast_throw`) and a frame shake UNDER the
  lightest one a landed blow gets: nothing has been hit yet.
- **TWO VOICES, ITS OWN** — `wand_charge` climbs and must RESOLVE at the throw (the raise is `CAST_DUR` ×
  `CAST_AT` ≈ 0.30 s, so it is a 0.40 s voice), `wand_cast` is a struck-crystal crack. A priest's cast is a
  throat and nothing done with a rod is a throat.
- **THE HARNESS HAS TO FIRE THE RELEASE ITSELF.** `castToThrow` drives the POSE past the throw without going
  through `game.throwBolt`, so `throwBoltForShot` throws the sparks too — otherwise every "the throw" still
  is a picture of the pose with none of the FX that fire on that exact frame in it. `castToCharged` stops one
  frame earlier, which is the only frame the gather's ramp and the light's swell can be judged on.

## The world

### The map is data, and the editor owns it

`worlds/*.world` are versioned text files of authoring OPS (`worldfmt.zig`); `env.materialize` replays
them. Nothing about the world is authored in Zig. Ops: `at`, `belt`, `disc`, `ring`, `line`, `ivy`,
`edge`, `cover`, plus `zone`/`clear`/`runway`/`foe` tables. Beside the shipped map,
`02_brood_arena` and `03_bone_court` hold one fight each; a test loads and replays all of them.

- **THE MAP STORES THE AUTHORING, NOT ITS OUTPUT.** A wood is one `belt` of 260 attempts, not 260
  coordinates — readable in a diff, and a density dial re-expands it.
- **EVERY GENERATOR OP CARRIES ITS OWN SEED.** One shared stream meant inserting a belt re-rolled
  every op after it, so no edit was ever local. Load-bearing.
- **ORDER IS MEANING.** Ops replay in file order because later ones read what earlier ones placed.
- **ONE FIELD TABLE DRIVES THE WRITER AND THE PARSER** (`fieldsOf`), walked at comptime in TABLE
  order. `std.meta.fields(Op)` reads the STRUCT's order and silently writes the wrong column.
  Unknown keys and missing fields are LOAD ERRORS; a missing or broken map PANICS with file and line.
- **FLOORING IS TWO GRIDS** — `soil` (material id) and `soilCov` (coverage 0..255). An edge is just
  where the author left coverage low. The paint rule is `lerp(here, opacity, falloff)`: painting below
  what is there THINS it and repeated passes converge instead of running away. A cell holding a
  different material is CONTESTED — the stroke wins only where it would cover more. `BRUSH_CORE`
  (0.55) keeps the middle solid.
- **HOW A PATCH ENDS IS PAINTED, NOT DERIVED** — a third grid (`Map.soilEdge`, one `wf.Edge` per cell)
  beside the material and the coverage, picked in the brush panel like the radius and the opacity. It is
  the STROKE's and not the material's: six materials cannot carry eight shapes, and the point is to lay a
  tiled courtyard and a torn scree of the same stone in one world. Eight shapes — `blend`, `natural`,
  `frayed`, `jagged`, `straight`, `tiled`, `scallop`, `speckle` — and their ordinals are pinned to the
  shader's `edgeShape()` by a comptime assert, so an inserted row is a compile error and not every stroke
  in every map silently re-pointed.
- **AN EDGE HAS THREE KNOBS AND THEY WERE FUSED INTO ONE BOOL** — how far the lookup WANDERS off the
  authored line, at what WAVELENGTH, and whether the boundary CUTS or feathers. The old `hardEdge` bool
  reached only the last of them, and the ±1.7 m wander was applied to the material ID *before* anything
  was asked, so a boundary wobbled whatever its policy said and **nothing could produce a straight edge —
  the thing being straightened was not the thing being bent.** The policy is now read FIRST, at the
  unwarped position, because the warp is what the policy decides.
- **THE EDGE MAP IS DILATED ONE CELL AT UPLOAD** (`gfx.dilateEdges`). A boundary is drawn from both sides
  and the shader must read the same policy either way; undilated, a tiled courtyard came out snapped
  looking outward and soft looking in, which is two edges. It is POINT-sampled for the id map's reason: a
  bilinear read halfway between `tiled` and `jagged` is an ordinal nobody authored.
- **A CELL IS 5 m** (`SOIL_N` 112 over a 560 m world), which is the floor on how fine any of this can be.
  Warps under about half a cell do not survive the coverage staircase.
- **AN OLD MAP COMES UP UNCHANGED** — no `soiledge:` row means a world written before the grid, and every
  cell takes the edge its material used to imply (`fillLegacyEdges`: stone cut, everything else soft). The
  row is only written when some stroke asked for something else (`edgesAllDefault`), so no existing world
  file changed. **WATER'S COAST DOES NOT USE ANY OF THIS YET** and it may not use it the same way: the
  water field is ONE field feeding the look *and* the wading, so an edge warped in the shader would put
  the coast you see somewhere other than the coast you walk into. It has to be baked into the field in
  `env.uploadWater` instead.
- **WATER IS PAINTED, ITS COAST DERIVED** — one bit per cell → a signed distance field (128 is the
  waterline). One field, three effects, so they cannot disagree. The sheet is ONE world-spanning quad.
- **PROPS CAN LEAN** (`lean`/`leanDir`) about the prop's GROUND ORIGIN, so the base stays planted and
  the culling sphere is unchanged. `buildSolids` carries the footprint with it.
- **`buildSolids` RESETS** — `materialize` runs it twice and an appending version doubles every
  collider in the world.
- Props carry the index of the op that placed them, which is what makes a generated rock selectable.
- **A MULTI-LINE RECORD ATTACHES TO THE ONE ABOVE IT** — the same running-cursor idea the RLE grids use, so the
  grammar stays one line per fact. `when:`/`do:` belong to the last `trig:`, `who:`/`say:`/`act:`/`then:`/`ask:`
  to the last `node:`, and `need:`/`gets:` to the last `ask:`. A part with nothing above it is a LOAD ERROR.
  `act:` may not be written after a choice, or its action run would swallow the choices' own.
- **PROSE LIVES IN ONE ARENA** (`Map.dtext`, `Span`), not in a per-node character cap that would be an
  arbitrary sentence length. `#` still starts a comment, so no authored line may contain one.

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

  **`npc:` RECORDS ARE APPENDED, NEVER INSERTED** — `near npc=0` is an INDEX into that table (SC1's own
  spawn-index form, and bg2's), so putting a new person above an existing one silently repoints every
  condition after it. `foe:` and `wf.FoeKind` have the same rule for the same reason.

  Conditions: `always`, `never`, `flag N=0|1`, `counter N <cmp> n`, `timer N=done|running`,
  `elapsed <cmp> secs`, `region x z x1 z1`, `near npc=i r=m`, `talked dlgId`, `deaths foeKind <cmp> n`,
  `alive foeKind <cmp> n`. Actions: `dialog dlgId`, `text …`, `flag N=0|1|flip`,
  `counter N set|add|sub n`, `timer N=secs`, `wait secs`, `preserve`. `<cmp>` is `<` `<=` `=` `>=` `>`.

### The day (`daynight.zig`)

One number — `Game.day.hour` — and every colour and every shadow in the world is a function of it.

- **ONE DIRECTION CASTS AND THE SHADER KEYS OFF IT** (the old law, unchanged): `keyDir` is the SUN while the sun
  is up and the MOON once it is down, `gfx.Scene.setHour` is its only writer, and it moves `gfx.sun` and
  `gfx.sunReach` together. The sun rises at 6 on bearing 100 and sets at 20 on 262; the moon is the ANTI-SUN, so
  one of the two is always up and the world is never unlit.
- **THE SKY DRAWS THE TRUE PATH, THE SHADOWS DO NOT.** `keyDir` FLOORS the casting altitude at `KEY_ALT_MIN`
  (15°) while `sunDir`/`moonDir` keep the honest angle for the disc. A 2° sun throws a 300 m shadow the 108 m
  ortho box cannot hold; the eye reads the disc's height off the horizon and the shadow's DIRECTION off the
  ground, and never solves one from the other. That is the one place the two are allowed to disagree.
- **THE TEXEL SNAP IS TAKEN IN THE LIGHT'S OWN BASIS** (`gfx.lightBasis`). Rounding world x/z to the texel pitch
  only lands on a texel while the light looks down a world axis. With a sun that sweeps, a world-axis snap stops
  snapping and the shadow edges crawl.
- **`Palette` IS THE WHOLE LOOK OF AN HOUR**, keyframed at nine hours and blended with the ease taken off both
  ends (a linear walk puts a corner in the light at every row). Wants retuning? Move a row, not a shader.
- **ITS TWO HALVES ARE ON DIFFERENT SCALES.** `key`/`ambGround`/`ambSky`/`haze`/`hazeBank` are read by the SCENE
  shader, which gammas its output — so they are PRE-GAMMA and near-black. Every `sky*`/`cloud*` value is read by
  the SKY shader, which gammas nothing — those are LITERAL SCREEN VALUES. Authoring the sky pre-gamma is what
  reads as a black hole over a blazing noon. **And at the dark hours `haze` must sit UNDER what the ground is lit
  to**, or the distance comes out brighter than the foreground and reads as fog rather than nightfall.
- **THE ANCHOR IS NOT A KEYFRAME.** `SHOT_HOUR` (17:27) is the hour that reproduces `gfx.SUN_DIR` — the light this
  game was authored, measured and photographed under, and the bearing `shots.LIT_YAW` is framed off. `SUN_ALT_MAX`
  and `SHOT_HOUR` are SOLVED from it; move `AZ_RISE`/`AZ_SET` and you solve them again rather than nudge them. Two
  tests pin the direction and the palette row. `--shot` pins and FREEZES that hour (`game.pinHourForShot`) — a
  clock running through a 362-frame harness re-lights the sequence as it goes.
- **The controls.** Menu > Debug > `Hour` (Left/Right scrub, Shift coarse, hold to sweep, Confirm holds it); in the
  EDITOR, `,` and `.` sweep it and Shift runs (the clock is held in the editor, so those are the only writers).
  A BONFIRE offers `Rest until morning` / `Rest until evening` — always FORWARD (`hoursUntil`), and asking for the
  hour you are on costs a whole day. Nothing is restocked there: `hero.sit` made him whole when he sat down.
  **THE TWO ROWS ARE THE TWO HALVES OF THE CLOCK, AND EVENING IS AFTER DARK** (owner's call): morning is 8:30 in
  the clearest light of the day, evening is `EVENING_HOUR` — 9 pm, an hour past `SUNSET`, **with the sun DOWN and
  the moon already casting**. It is deliberately NOT `SHOT_HOUR`: the anchor is the golden hour with the sun still
  well up, so a row named "evening" that handed you the anchor did nothing you could see. A comptime assert pins
  it past the horizon, a test pins `!isDay` and the key under a quarter of the anchor, and `shots/147` is that
  hour exactly rather than a number beside it.
- **AND THE FIRE TOUCHES THE CLOCK NOWHERE ELSE** (owner's call). Sitting down used to pull the whole world into a
  local dusk whatever hour it was — a `dim` uniform in both shaders, riding on top of the palette. That dial is
  GONE: the hour you walk in at is the hour you sit in, and the two `Rest until…` rows are the only thing at a
  fire that moves the light.
- Verify with the strip: `shots/140`–`147` are eight hours of ONE view shot into the light's own quarter, and
  `148*` three overheads of the same ground. The arc is the test — a frame that reads like its neighbour is an
  hour the palette is not earning.

### Elevation

The world is a HEIGHTFIELD you sculpt (Ground layer > Raise/Lower/Smooth/Flat), stored as one
QUANTISED height per lattice point (`HEIGHT_N` 2.5 m, `HEIGHT_STEP` 0.25 m, biased so `HEIGHT_ZERO` is
the old flat ground). Quantised because the file is TEXT and the writer is a run-length encoder.
The mesh is TILED (`TCHUNK`), with normals from the FIELD so two tiles agree at their seam.

- **A FLAT MAP IS THE OLD WORLD, EXACTLY** — `heightAny` false means one world-spanning quad,
  `groundAt` returns `GROUND_Y`, and no `hgt:` record is written.
- **NOTHING SAMPLES THE MAP DIRECTLY.** Env keeps the live copy the visible mesh was built from and
  `wf.sampleHeight` is the ONE sampler both owners call, so the hero cannot walk off the mesh he sees.
- **EVERY PROP PLANTS AT THE HEIGHT UNDER IT** — `uploadHeight` must run BEFORE `materialize`, and a
  sculpt stroke re-materializes on RELEASE.
- **TWO RULES DECIDE EVERY STEP** (`env.walkStep`), either one passing: the rise ahead is under
  `STEP_UP` (0.55 m, sized to the encoding — two risers walkable, three a wall), or within
  `MAX_SLOPE` (tan 40°).
- **MEASURED OVER A FIXED LOOKAHEAD (`STEP_PROBE`), NEVER THE FRAME'S OWN TRAVEL.** The one thing here
  that cannot be got wrong quietly: against frame distance a 240 fps hero ratchets up a vertical
  cliff. A test pins the rule across four frame rates.
- **A REFUSED STEP IS NOT A STOP** — the uphill component is removed and the rest is taken at full
  length. A hard block would put invisible corners all over a hillside.
- **FOES GET THE SAME RULES** as a POST-STEP GATE (`game.gateTerrain`). Airborne foes are exempt from
  the terrain rule and from being shouldered — never from `env.resolveActor`, or a pounce crosses a
  wall. That push-out is NOT rate-limited.
- **`pos.y` IS THE GROUND UNDER AN ACTOR**, written in ONE place (`game.groundActor`), EASED not
  snapped (`GROUND_RISE_RATE`/`GROUND_FALL_RATE`) — the camera rides the shoulder, so snapping kicks
  the frame. Past `GROUND_SNAP` it plants instead.
- **EVERY WORLD POINT ON AN ACTOR IS MEASURED FROM `pos.y`** — shoulder points, `centerWorld`,
  `lockPoint`, `topWorld`, crush points, dust. From the datum instead, a foe on a bank keeps its HP
  bar down in the field.
- **THE CAMERA SHORTENS ITS BOOM RATHER THAN BURYING THE EYE** (`camera.followClear`); lifting instead
  would tip the view toward looking straight down as you climb.
- **BUT IT GIVES WAY TO TERRAIN ONLY, NEVER TO ITS OWN PITCH** (owner: it zoomed in hard when tilting up
  onto a tall foe). An up-tilt puts the eye LOW on purpose — that is `game.lockPitch` framing an ogre — and
  the probe answered by eating boom to buy the altitude back, so every lock onto something tall read as a
  shove toward the hero. Only ground standing PROUD of the hero's own level (`GROUND_RISE`, just under one
  terrain riser, so quantisation cannot bill a step) is worth paying distance for; on the flat the skim
  clamp lifts the eye those last few centimetres and the boom stays the player's.
- **THE HERO LEANS INTO THE HILL** (`hero.slopeLean`, 0.55 of the slope capped at 16°) through the
  SAME `rx(bodyPitch)` term as the run lean — same motion, same hinge.
- **THE TERRAIN RECEIVES SHADOWS BUT DOES NOT CAST.** Self-shadowing a heightfield off a 108 m ortho
  box puts acne everywhere the surface grazes the sun.

### Performance — how a 560 m world stays cheap (`env.zig`)

- **UNIFORM GRID (CSR).** Props bucketed by 16 m cell into two indexes (structures, flora), built by
  counting sort into one flat array. Each cell carries the MAXIMA its pass needs, so a whole cell can
  be rejected before any prop in it is looked at.
- **THE LIT PASS culls per cell then per prop** — four frustum side planes plus each kind's `view`
  distance (stricter and cheaper than near/far planes).
- **THE DEPTH PASS culls by SHADOW REACH, not camera distance.** A caster throws its shadow ~1.5× its
  height sideways (`SUN_REACH`), so a prop matters iff its footprint plus that reach can touch the
  ortho box (`castsInto`). A naive distance cull clips real shadows.
- **COLLISION + ARROW FLIGHT query the grid**, never the whole solid list.
- **Check it, don't trust it.** Menu > Debug > Stats prints the live counts and `--shot` captures
  them. If `drawn` approaches `props`, a culler has been defeated. Caps are init-time PANICS
  (`MAX_PROPS`/`MAX_SOLIDS`/`MAX_SOLID_REFS`) — a silently dropped collider is a walk-through wall.
- **THE OCCLUDER FADE** (`env.markOccluders`): a prop between lens and hero goes thin, keyed to how much
  of him it hides. Three rules keep it from reading as a switch: the geometry sets a TARGET and an EASED
  ramp walks you there (`OCCL_IN` 0.16 s, `OCCL_OUT` 0.34 s — out is slower, and `easeShape` takes the speed
  off both ends, since a constant rate leaves solid and arrives at the floor with the same abruptness); it
  stops being in the way over a BAND not a plane (`OCCL_DEPTH_BAND`); and `OCCL_MAX` counts what is in
  flight, both directions. The shape is a pure function of where the value SITS, never of where a travel
  began — `fadeTo` moves under it every frame the camera does, and an anchored ease restarts on each one.
- **EVERYTHING THINS EXCEPT WHAT SAYS `solid`** — architecture, cliffs, the water sheet, the bonfire (its
  smoke draws down `drawVeils`, which carries no fade). The flag is that way round because as an opt-in
  `fades` every kind added afterwards opted out by silence, and boulders, statues, lanterns and saplings
  blotted the hero out solid. Flora is exempt structurally: `markOccluders` walks `stx` only.
- **THE OCCLUDER VOLUME IS NOT THE COLLIDER** (`props.Blocker`, `Info.occl`). A collider is sized for what
  you WALK INTO, an occluder for what you SEE THROUGH, and on a tree those differ by metres — a conifer's
  collider is a 0.58 m pole against boughs that block the view at 3.4 m, so looking through the canopy
  scored nothing and the tree stayed solid. The trees carry cylinders taken off their own mesh builders
  (bole then crown; `y0`..`y1` off the foot, since one cylinder cannot be narrow low and wide up top).
  A kind with no `occl` falls back to the colliders plus `OCCL_SKIRT`, which is right where the two shapes
  agree — a pillar, and an ARCH, whose opening must stay see-through.
- **COVERAGE OPENS THE GATE, DEPTH SCALES THE ANSWER** (`thinOf`). `OCCL_MIN` is a coverage figure and
  nothing else. Multiplied together before the threshold, a mass a metre in front of him was discounted
  under it and stayed solid at the one moment it was most in the way.
- **A THINNED OCCLUDER DRAWS LAST, AFTER EVERY OPAQUE THING, AND BACK TO FRONT** (`env.drawThinned`). It
  draws with the depth MASK OFF, so it writes no depth — and left in cell order with the rest, the HERO came
  afterwards and composited at FULL opacity straight over it. He went from hidden to solid on the one frame
  the mask came off, and the ramp underneath only ever dressed the TREE against the terrain: an instant
  reveal wearing a fade. Drawn last, the tree's alpha is what mattes HIM, so the reveal IS the ramp.
- **AND IT BLENDS ONE LAYER PER PIXEL.** A trunk is not a sheet — buttress roots, boughs and the far side of
  its own bole stack three or four surfaces along the ray, and blended one after another the alpha COMPOUNDS:
  the number stops meaning what it says and the mass comes out banded where the layer count changes. So each
  prop lays its own depth down first with the colour buffer held (`dst = 0·src + 1·dst`, rlgl having no
  colour mask), and the pass after it draws under rlgl's LEQUAL, which only the NEAREST surface satisfies.
- **A FULL LIST GIVES ITS SLOTS TO WHAT HIDES HIM MOST — TAKEN OFF SOMETHING STILL SOLID** (`wantFade`).
  First-come meant cell-walk order decided. But nothing outside the list is ticked, so dropping an entry
  that has already left solid either strands it thin or snaps it back; the victim is the least-thin ask
  among those still AT solid, and with none of those the ask waits a frame instead. A tree a frame late in
  getting out of the way is not something the eye can see; a tree jumping back to solid is.

## Triggers, folk and dialog

**IT IS STARCRAFT'S TRIGGER SYSTEM, ON THIS WORLD.** A trigger is CONDITIONS and ACTIONS; every condition must
hold, then the action list runs in order. `worldfmt.zig` holds the definitions as map data, `trigger.Runtime`
holds everything that changes, `dialog.Session` is the one conversation that may be on screen, and `npc.zig` is
the body you speak to. Nothing about any of it is authored in Zig.

- **THE GENERAL-PURPOSE STATE IS WHAT MAKES IT COMPOSE**, not the condition vocabulary: named switches
  (`flag`), named integer counters (what SC1's death counts were really for) and countdown timers. Without
  them every new bit of story state wants a new condition kind.
- **A NAME IS INTERNED TO A SLOT AT LOAD**, so a condition costs two bytes instead of a string, and the map
  carries the `flags:`/`counters:`/`timers:` tables so the file stays self-describing.
- **EVERY OTHER REFERENCE IS RESOLVED AFTER THE WHOLE FILE IS READ** (`link`) — a dialog may be declared below
  the trigger that opens it, and an `ask:` may point forward at a node. ORDER IS MEANING for ops because each
  reads what the last one placed; a NAME is not that kind of dependency. An unresolved one is a LOAD ERROR.
- **EVALUATED EVERY FRAME, NOT ON A CYCLE.** SC1 walked its list on a slow tick, which is the entire reason
  "hyper triggers" existed. A conversation opening a beat after you crossed the line is a bug here, so a
  PRESERVED trigger is held off by `REPEAT_GUARD` (0.5 s) instead — without it `always` + `preserve` fires
  sixty times a second and never lets go of the screen.
- **A CONDITION IS LIVE, NEVER STICKY.** `region` is SC1's Bring exactly: true while he stands in it. Two
  conditions that come true at different moments are what the SWITCHES are for, and that indirection is the
  idiom rather than a shortcoming of it.
- **AN EMPTY `when:` LIST NEVER FIRES.** `always` is a condition you write down, or a trigger whose conditions
  were still to come goes off the moment the map loads.
- **A `dialog` ACTION BLOCKS ITS OWN LIST AND NOTHING ELSE** (SC1's Transmission), and so does `wait`. Every
  other trigger keeps being asked. Only one conversation may be up, and a trigger that wanted the screen is
  simply not advanced that frame — deferred, never dropped.
- **`deaths` IS MAINTAINED BY THE ENGINE**, off `justDied` through `eachTarget` — the foe contract's one-frame
  edge, because a latch (the sac's `killed`) reads true every frame after and would bill one death sixty
  times. The egg sac has no such edge, so the brood's own `bursts` counter is what bills it.
- **THE SCRIPT LAYER IS ARMED WHERE THE MAP CHANGES, NOT WHERE THE HERO DIES** (`game.armScript`): a load and
  every way out of the editor. The story he has already heard is not undone by dying, any more than his bag is.
- **ONE BUTTON, ONE WRITTEN PRIORITY ORDER** — bonfire, then whoever is standing there, then a box
  (`game.interact`). The HUD prompt reads the same order, or it names a button the press will not honour.

### The dialog panel

- **IT IS SIZED TO WHAT IT HOLDS**, growing upward off a fixed bottom edge. Pinned to a fraction of the screen
  it is half empty on a two-line exchange and cramped on a long one.
- **A GATE HIDES A LINE, IT DOES NOT GREY IT.** bg2's editor carries a `disabledMessage` for a refused choice;
  nothing here has one to show, and a greyed row with no reason is worse than a row never offered.
- **YOU MAY NOT WALK OUT MID-SENTENCE.** There is no cancel — a conversation is left through one of its own
  endings, which is what lets `talked` mean "has heard this" and not "has seen the first line of it".
- **THE WORLD'S HUD GOES AWAY BEHIND IT**, as it does at a bonfire: the panel takes the bottom of the screen,
  which is exactly where the cross and the prompt live.
- **A NODE'S `act:` FIRES ON ARRIVAL AND A CHOICE'S `gets:` ON THE PICK**, both straight through
  `trigger.Runtime.apply` — an action means the same thing whichever fired it, and two copies of that switch
  would eventually disagree.

### The wanderer (`npc.zig`)

Not a foe: no `Vitals`, no `Leash`, no blade. Do not let the foe contract grow into it by accident.

- **A MAN STANDING STILL IS THE HARDEST THING TO ANIMATE.** An idle that is only a breathing bob is a mannequin
  with a pulse, so THREE clocks run at rates that never line up — breath, a weight shift, a head drift — and
  because the periods are incommensurate the loop never shows.
- **THE WEIGHT SHIFT IS A PELVIC LIST, NOT A SLIDE.** Translating the pelvis sideways carries both hips with
  it and `legChain` solves each leg straight down from its own hip, so both feet travel too — a man skating.
  A roll about the pelvis raises one hip and drops the other, which is what standing on one leg does.
- **AND ITS DROP IS PAID BACK AT THE PELVIS.** At rest this rig's leg is EXACTLY straight (pelvis 0.530·H,
  ankle 0.039·H, thigh + shank 0.491·H), so a pelvis a millimetre below rest has nowhere to put the millimetre
  and the sole goes through the floor — there is no foot IK, and the STANDING pose has none of the gait's knee
  flexion to absorb one. Lift by `hx·sin(list)` and the low hip stays on its plane.
- **NO PITCH AT ALL AT THE ROOT**, and here the waist-hinge law is not a taste call: a root pitch rotates the
  LEGS, so one degree of stoop levers a just-planted foot half a centimetre into the ground. A stoop is
  thoracic anyway — the whole of it lives in the spine and the chest.
- **HE TURNS FIRST, THEN WALKS** (`TURN_GATE`). Stepping off before he is pointed at it makes travel disagree
  with facing, which IS a sidestep as far as the shared gait is concerned — a crab-walk, and the strafe path
  carries eight centimetres of foot-clearance tolerance nothing here needs.
- **THE STAFF IS THE OTHER HALF OF THE GAIT.** A walking staff plants with the OPPOSITE foot, so the staff arm
  does not swing freely — it drives the pole down once a stride while the free arm swings at full amplitude.
- **AND WHERE IT POINTS IS AUTHORED IN THE WORLD, NOT IN THE WRIST** (`warrior.swingTilt`'s law,
  `hero.shieldFit`'s). Built down the wrist's own −Y it inherits the entire arm chain: 46° off plumb at rest,
  and at the plant it lay out flat in front of him like a lance. The fit BILLS THE ARM for its own abduction
  and pitch, leaving `STAFF_TILT` to mean degrees off plumb in the world.
- **THE BOOT IS THE HERO'S FOOTPRINT EXACTLY**, and not as a style choice: the gait curves plantarflex the
  ankle to a fixed angle at toe-off, so a longer toe is a longer lever below the plane and `legChain` can only
  level the ankle, never lift the body. Three centimetres of extra toe raked three times as deep.
- **THE TWO HEAD VARIANTS ARE WHAT MAKES TWO OF THESE TWO PEOPLE** — hood up, hood back, picked by seed.
  Everything else varies through the POSE, which costs no mesh.
- **VALUE CONTRAST BETWEEN TWO LARGE AREAS CANNOT SURVIVE FULL DAYLIGHT ON THIS SUN.** A sunward face reads
  `255·(albedo·1.72/255)^(1/2.2)`, so albedo 40 comes back at 142 and 58 at 168: darken the second mass enough
  to separate in shade and it blows out beside the first at noon anyway. Layer on HUE, which the sun does not
  flatten, and spend the value contrast only where the area is small (`LINEN`) or is a hole (`HOOD_IN`).

## Sight and leashing

**A LOOK IS A SEGMENT AND IT IS TESTED EXACTLY** (`collision.blocksSight`) — one segment-vs-capsule
test per solid, never a walk of samples (a step fine enough costs real time over 20 m; a coarse one
lets a fence post through). It passes OVER anything whose blocking height is under both ends.

**THE GRID IS WALKED, NOT COPIED** (`env.sees`) — `nearSolids` truncates at `MAX_NEAR`, which over a
20 m line through a wood quietly drops the wall it was asked about.

**IT IS ASKED ONCE A FRAME, BY THE GAME** (`game.markSight`) for every foe inside `SIGHT_R`, stamped
on that foe's `Leash`. Creatures do not ask it themselves — the prop grid belongs to `env`.

**WHAT IT LOSES IS ITS EYES, NOT ITS MEMORY.** `Leash.blind()` needs `SIGHT_MEMORY` (6 s) with no
line, longer than `LEASH_CALM`, so breaking sight can never shed a foe faster than walking away does.
**A blow outranks blindness** — `roused()` beats `blind()`.

The leash is one struct every creature embeds:

- **START FAR, STOP NEAR** — turns for home past `foe.leashR(AGGRO_R)`, stops inside `LEASH_HOME_R`
  (3 m). That gap IS the debounce.
- **THE TETHER IS THE CREATURE'S OWN NOTICE RING PLUS `LEASH_SLACK` (6 m)**, not one authored number,
  so a toad and an ogre give up after the same few unproductive metres. A flat 30 m was also THE
  SPACING BETWEEN CAMPS, so a tether reached the next encounter.
- **ONLY AFTER `LEASH_CALM` (4.5 s) WITH NO BLOW GIVEN OR TAKEN**, and only once the hero has left the
  patch — a foe with him standing in the ground it guards has no business turning round.
- **AND THE PATCH IS A PLACE, NOT A SEPARATION** — both ranges in `Leash.tick` are measured FROM THE POST:
  how far the CREATURE has come, and how far the HERO is. Asked as the gap between the two BODIES the
  notice ring was doing a job it is the wrong size for — a creature could only let go once the hero had
  out-run it by its own full aggro (24 m for an archer), and it walked the whole time that gap was opening.
  Tethers nominally 17-30 m long measured out at 34 m (ogre) to 176 m (leechfly), which is the owner's
  "monsters simply chase you forever". A test walks the field and pins each one to its own leash
  (`game.zig`, "NOTHING CHASES FOREVER").
- **A WALK HOME IS NOT BLIND** — step back into the patch, or land one blow, and it turns on the spot.
- **A FIGHT IN PROGRESS OUTRANKS THE TETHER, and that is not a leak**: `noteCombat` is stamped by every
  blow either side lands, so a leechfly that rides him for eighty metres is one that has been FEEDING the
  whole way. What a tether owes there is a prompt let-go once the biting stops, which is a CLOCK and not
  a distance.
- **RE-ENGAGING COSTS `REENGAGE_HOLD` (8 s)** in which it cannot try to leave again.
- **ONE PLAYER BLOW ROUSES IT FROM ANY RANGE for `PROVOKE_ROUSE` (14 s)** — a COUNTDOWN, not a level,
  because it has to outlast the walk. Only a `pierce` blade also snaps its facing back down the shaft.
- **KEEP AT IT AND THE LEASH BREAKS** (`PROVOKE_BREAK`, held `PROVOKE_HOLD`). The anti-cheese: poking a
  foe at the end of its tether and watching it walk away is free damage at no risk. Not gated on
  `pierce`, or the sword — the very poking it is named for — is exempt.
- **IT REACHES EVERY STATE MACHINE BY BENDING THE SENSED RANGE** (`foe.sensedDist`), not by bolting a
  second decision tree onto each. Only the DECISION sees the bent number; movement uses his real
  position. **Every decision, including the ones after a leap** — the kobold's dash and the archer's
  backstep both re-decided on the raw distance when they landed.

**Foe pacing:** the archer's BACKSTEP is a committed jump straight back, inside sword reach, on a 7 s
cooldown — it buys the shot back exactly once. An evade you can spam is a wall.

**A TELEPORT IS A JUMP, AND THE ROOTS REFUSE IT** (`shade.wantsBlink` → `foe.canLeap`). A blink does not
travel, it leaves the earth, so it is gated where the move is CHOSEN like every other leap in the game — and
that is what makes the wand's roots the answer to a haunting. It is also the one move that must not fire out
of a STAGGER: a creature that vanishes mid-flinch erases the punish window the flinch exists to open, so the
blow sets a latch (`spooked`) and the blink is spent at the next choose site, which reads as the thing
deciding it has had enough. Half a blink is `airborne()`, which is what exempts the jump from
`game.gateTerrain` — a step it never took cannot be walked back.

**A MOVE THAT CANNOT LAND IS NOT A DECISION.** The ogre's swipe passes clean OUTSIDE anything hugging its legs
(`swipeInner` 2.28 m) and collision holds the hero at 1.68, so toe to toe `classify` was spending two thirds of
a second on a guaranteed miss every time the slam happened to be cooling — and a parried slam's cooldown sends
it there every time. The pocket at its feet is something the player EARNS by getting inside; it is not
somewhere to be swiped at. A choose site tests the move's OWN band, not just its outer range.

## Saving, and the boot screen (`save.zig`, `menu.zig`)

**YOU SAVE AT BONFIRES AND NOWHERE ELSE** (owner's call). There is no Save row anywhere in the game: sitting
down IS the save, `game.tickRest`'s `justEntered` is the one line that writes one, and it lands in whatever
slot is being played (`g.slot`, ER's rule) without asking. **THREE SLOTS**, `save1.dat`…`save3.dat`, each with
a `save<n>.png` beside it.

- **THE FILE IS TEXT IN THE MAP'S OWN GRAMMAR** (`key: value`, `version:` first) for the map's reason: a save
  you can read is a save you can see what is wrong with. Unknown key, bad version or another map's name are
  LOAD ERRORS — a save is refused whole rather than applied in half.
- **THE BARS ARE NOT IN THE FILE, AND THAT IS THE POINT.** The one place a save is taken is a fire, and
  `hero.sit` runs `makeWhole` before the write — HP, stamina, focus, both flasks, both quivers, poison, ward
  and grease all settled. Storing them would be storing a constant beside the thing that derives it. The
  SHEET is out for the same reason one layer along: it is `ptree.Bonus.sheet()` of the tree below, and
  `game.applyTree` re-derives it on the way back in.
- **IT IS GATHERED AND SCATTERED THROUGH ONE VIEW** (`save.Slot`, `game.slotOf` — `bookView`'s shape and its
  reason): the save file owns no game state and reaches for nothing. Parsing goes into a `save.Data` on the
  stack FIRST and is committed only if the whole file read, so a half-read file is never a half-built
  character.
- **A LOAD LANDS IN A FRESH WORLD AND THEN OVERWRITES IT** (`game.loadGame`). Every array the file does not
  mention is at what a NEW game has rather than at what the last one left, and the order is load-bearing:
  `beginGame` is what sizes `chests.n` off the map and rebuilds the trigger ORDER, both of which the file
  writes into and neither of which it carries.
- **`beginGame` IS THE ONE ANSWER TO "WHAT IS A FRESH GAME"** — `Game.init` and New Game both come through
  it. As a second list in `init` it is the copy nobody plays through.
- **THE THUMBNAIL IS A POST-DRAW GATE, NOT A DECISION AT THE EDGE** (`game.takeSlotShot`). `justEntered`
  fires at the BOTTOM of the fade-in where the screen is black, so what is OWED and when it can be PAID are
  different frames. Taken after the world is drawn and before the HUD and the fire's list go over it, so the
  picker shows him at the fire rather than a menu. The harness calls the same function at the same point
  (`shots.bonfireShoot`) — `--shot` never runs the loop, so that is the only thing proving the grab works.

**THE BOOT SCREEN IS ITS OWN SCREEN, not the pause card with different rows.** New Game / Load Game /
Options / Editor / Quit, over a live 3D backdrop the camera walks slowly round (`game.BOOT_*`).

- **IT HAS NO BACK AND NO CONTINUE**, and Select/Start are refused while it is up (`Menu.booting`) rather
  than gated at each call site. **QUIT IS ITS ROW**; from inside a game the way out is `Back to Title`.
- **`menu.home` IS WHICH ROOT A SUB-SCREEN RETURNS TO.** Options hangs off both cards and the editor is
  reachable from both, so a hard `.main` dropped you into the pause menu of a game nobody had started.
- **THE BOOT CAMERA IS ASKED FOR AFTER `menu.update`, NEVER BEFORE.** `dist`/`pitch` are the PLAYER's zoom
  and tilt and nothing in play resets them, so stamping the title framing on the frame New Game was pressed
  handed the new character a camera seven metres back. (Reported as "you zoomed out the game when playing".)
- **BOTH ROWS ASK WHICH SLOT** (owner's call). New Game used to take the first empty one without asking (ER's
  own) and only show the picker when all three were full — so the one press that decides where a character
  LIVES was the one press that never said where. Three slots is few enough that choosing is the point of
  having them.
- **A SLOT CAN BE THROWN AWAY, AND IT IS THE ONLY PRESS IN THE GAME THAT DESTROYS ANYTHING** — so it is armed
  on one button (`hud.BTN_QUICK`, named off the crib like every other binding) and done on a SECOND, and the
  second is the ordinary Confirm, because by then the row has become the question. Walking off the row, Back,
  or re-opening the picker all disarm it. **BOTH FILES GO** (`save.erase`): a picture left standing beside a
  save that is gone is the one thing the picker's own rule forbids. The menu holds no game state, so it hands
  `Action.deleteSlot` up and `game.zig` does the removing, the re-survey and the re-read of the pictures.
- **A ROW THAT CANNOT BE PRESSED IS DRAWN SO** (`Menu.rowLive` + `Card.dim`, `TEXT_OFF`) — one predicate read
  by the PRESS and by the picture, so a row can never look available and do nothing. The cursor still lands
  on it: a row you cannot reach is a row whose reason you cannot read, and the reason is the footnote.
- **THE PICKER'S THREE TEXTURES LIVE NO LONGER THAN THE PICKER** (`menu.loadShots`/`unloadShots`).
- **ASCII ONLY, like every string in the game** — the atlas has no em dash and one renders as tofu.

## Controls (`game.zig`)

Keyboard+mouse or gamepad; the pad follows **Elden Ring's default layout** (ER is the north star
throughout).

**WALK vs RUN (owner's definition):** the whole left-stick range is WALK (tilt scales walk speed
only), and RUN is exclusively the hold-B / hold-Shift sprint. Gate run-only flourishes on `sprintB`,
not the stick-speed `runB`.

- **Mouse:** hidden over the window and drives the camera, but NEVER locked/captured — push it past
  the edge and it comes back as a normal cursor. Do NOT reintroduce `disableCursor`/pointer-lock.
- **Committed actions with an ER-style input queue** — an attack/roll pressed mid-action buffers in
  ONE slot (last press wins; a same-frame roll outranks attack) and fires at the earliest exit. A
  queued roll leaves in the direction HELD at fire time, not pressed.
- **INTERACT IS Y, EVERYWHERE** (owner's call) — `game.INTERACT_PAD`/`INTERACT_KEY`, and the keyboard mirrors
  the pad letter for letter so no crib ever has to name a key. It is the one face button ER leaves free: A is
  reserved for the jump, B is the roll, X is the quick item. The dialog panel takes it on top of the menu
  Confirm, so the button that opened a conversation is the one that walks through it. The quiver's keyboard
  cycle moved off Y to `ARROW_KEY` to make room.
- **Guard or CAST:** hold L1/LB or RMB. The button belongs to the HAND, not the shield.
- **Aim or PARRY:** L2 is that same hand's SKILL slot and is routed the same way — a raised bow aims on the
  HELD level (or RMB with the bow out, free to take because the bow already took the shield), boards parry on
  the PRESSED edge (`PARRY_KEY`, since RMB is spoken for and Shift is the sprint).
- **THE RIG TILTS ONTO WHAT IT IS LOCKED TO** (`game.lockPitch`). The boom's pitch IS the view's, so the
  right number is the angle from the EYE down to the mark — a toad at your boots tips the camera down, an
  ogre whose chest is two and a half metres up tips it back. A fixed pitch framed the grass under a giant and
  the sky over a toad, and both of those are the one thing you are trying to look at. Measured off the LIVE
  eye rather than solved, which makes it a convergent feedback loop (gain `boom / (boom + range)`, under 1
  everywhere the near guard does not fire) that `camera.aim`'s ease damps the rest of the way. It is why
  `camera.PITCH_MIN` is -0.38 and not the -0.20 the free look ever asked for.
  **THE TILT UP IS EARNED BY HEIGHT *AND* BY CLOSENESS** (owner: only bring the camera low for a tall enemy
  when it is NEARBY; further off a lock behaves like any other), and it is a SHARE rather than a switch —
  `lockTiltShare`, the product of two smoothsteps, so neither gate can step. Height alone used to be the
  whole rule, so an ogre across the field still pulled the lens up off the ground it stood on; and a hard
  height threshold snapped every time a leechfly climbed through it. Down is still free and still ungated.
  **DOWN IS FREE; UP IS EARNED** (`LOCK_TILT_TALL`, owner: it was tilting up too much and too often). A
  kobold, a skeleton or a shade is framed whole from the default pitch already, and lifting the lens onto one
  only takes the ground out from under it — so the up half is gated on how far the creature reaches into the
  sky OFF ITS OWN FEET (`topWorld`), which keeps a kobold standing on a rise a kobold. Only the ogre and the
  Rooted clear it standing, and the LEECHFLY clears it once it has climbed and not before, which is the one
  answer that has to move with the creature.
- **Lock-on:** R3 / middle mouse; a flick cycles. Suspended entirely while aiming. Two ER exceptions:
  a hold-B sprint faces TRAVEL, and an attack's recovery tail re-squares (`ATK_RETRACK`).
  **YOU CANNOT FIX ON WHAT YOU CANNOT SEE** — a foe behind a wall is not offered (`game.canSee`), but
  a HELD lock fades rather than switching (`LOCK_BLIND_HOLD` 1.1 s), or a pillar crossing the line
  mid-circle throws the camera off.
- **Cross/A = JUMP** (keyboard `V`), matching ER — see "The jump" under Combat. Not a clash with the menu
  Confirm on the same button: every screen that takes Confirm holds the world still while it is up, so the two
  can never be asked on one frame. `hud.BTN_JUMP` is named apart from `BTN_CONFIRM` because they are two
  bindings that happen to agree, and a rebind of one is not a rebind of the other.

## Hard invariants & gotchas

- **Coordinates:** ground is XZ, Y up. Hero faces +Z at yaw 0; `atan2(facing.x, facing.z)` is the
  facing angle.
- **Strafe sign:** the camera looks +Z from behind, so screen-right is world −X → `camera.rightXZ`
  MUST be `(−cos yaw, 0, sin yaw)`. Flipping it mirrors L/R walking.
- **VSYNC, not `setTargetFPS`.** `vsync_hint` before `initWindow`, no frame cap — `setTargetFPS` is a
  CPU-side limiter that never asks the driver to swap during vblank, so the swap TEARS in exclusive
  fullscreen, and two limiters fight on any panel that isn't 60 Hz.
- **Depth z-fighting:** `rlSetClipPlanes(CLIP_NEAR, CLIP_FAR)` (0.55, 320) at startup. The ground sits a hair above y=0
  (`env.GROUND_Y = 0.01`) so content is planted-to-slightly-embedded and never FLOATS.
- **Sun + shadows are STILL ONE source** — `gfx.sun`, solved from the hour (`daynight.keyDir`) and written only by
  `gfx.Scene.setHour`, feeding the shader, the shadow camera and `env`'s depth cull. `gfx.SUN_DIR` is now the
  ANCHOR the cycle is solved through, not what casts.
- **Shadow pass contract:** every caster draws through `game.drawCasters` (both passes, so transforms
  can't drift). drawMesh/drawModel use the MATERIAL's shader, so the depth pass swaps caster shaders
  (`setCasterShaders`) and runs BEFORE `beginDrawing`. Terrain and FLORA receive but do not cast. The
  ortho box tracks the hero, snapped to shadow texels so edges don't crawl, and tracks Y as well.
- **The hero is per-bone matrices, not `drawModelEx`.**
- **The scene shader gammas output (`pow 1/2.2`): author dark colours near-black.**
- **Vertex alpha is the EMISSIVE channel** (255 = fully lit; lower = self-lit).
- **A BIG SMOOTH MASS NEEDS A NEARLY-BLACK ALBEDO — and FORM BREAKS.** The hot key (×1.72) plus the
  gamma lift turns any mid-dark value pale on a large sunward face. The bigger the face, the darker it
  must start, and a dark smooth mass still reads as plastic without breaks.
- **TWO STONE MATERIALS.** `.stone` is rubble masonry, matte; `.marble` is dressed stone, veined, with
  the only real gloss besides steel and water — kept LOW, or it lays a wash over every sunward face
  and undoes the dark-albedo rule. Marble = columns/arches/statues; stone = walls/towers/rubble.
- **`gfx.Mat` is APPEND-ONLY** — the shader branches on the raw ordinal the whole way from 1 to 14, and the
  comptime asserts pin the TAIL (water 9 through bark 14). Pinning `water == 9` is what catches an insert
  anywhere below it, which is why the head needs no assert of its own.
- **THE FLAME MATERIAL IS THE ONE THING DRAWN SEMI-TRANSPARENT BY ITS MATERIAL** (the faded hero under
  an aim is the one drawn so by a per-draw uniform). Opacity is graded off the emissive
  (`FLAME_A_CORE`→`FLAME_A_TIP`); depth WRITE stays on so tongues don't stack into a brighter core.
- **BUILDER WINDING IS NOT CHECKED, AND FACE-DOWN GEOMETRY IS INVISIBLE.** A flat annulus swept
  outward-first points DOWN and raylib culls it. Sweep inner@a0 → inner@a1 → outer@a1 → outer@a0. For
  a ring, radial is the position direction and tangent is `(cos a, 0, sin a)`; for an arch ring at
  angle a, radial is `(−cos a, sin a, 0)`, tangent `(sin a, cos a, 0)`. `addBox` also accepts a
  NON-PERPENDICULAR axis triple and builds a skewed parallelepiped.
- **A CURVED SHAFT DRAWS ITS CURL ONCE AND APPLIES IT EVERY SEGMENT.** Re-rolled per segment it wanders
  instead, and a wander made of straight capsules is a chain of elbows. The total arc is the per-segment
  curl TIMES the segment count, so moving either the length or the count re-brackets the curl — the same
  bend spread over a longer run straightens into a stake.
- **A RING THAT OVERWRITES ITS OLDEST DOES IT SILENTLY**, so its size is arithmetic over what feeds it
  (every emitter's worst frame), asserted at comptime — never a round number that looked big enough.
- **A cylinder is CAPLESS** — an open end shows its culled interior. Cap with `addDome` or an
  axis-flattened `addBlob`; a flat cap constrains the piece to a world axis.
- **REPEATED BIG PROPS NEED VARIANTS.** One mesh placed sixty times reads as a periodic pattern; yaw
  and scale do not hide it. The three `bigtree` kinds and six `CLIFFS` exist for this, drawn through
  an op's weighted `mix=`. Long-wavelength variation beats per-instance noise.
- **A CULLER BUG LOOKS LIKE AN EMPTY WORLD, AND ONE-ORIENTATION TESTS MISS IT.** `View.fromCamera`
  sign-corrects its plane normals against the camera forward rather than assuming a handedness. Its
  test sweeps seven headings.
- **A LIGHT'S RADIUS MATTERS MORE THAN ITS BRIGHTNESS.** A 9 m torch in a 5×7 m chapel reaches every
  surface from every corner, so four summed to a flat wash however dim each was. Fire has to POOL.
- **Fullscreen shader passes must build ray/UV from `gl_FragCoord`** + a resolution uniform when drawn
  via `drawRectangle` — raylib maps rectangle texcoords to the tiny shapes-texture rect, so
  `fragTexCoord` is effectively CONSTANT. `drawTexturePro` blits are fine.
- **Retro pass contract:** with any filter active the frame renders into `Retro.rt` then blits through
  the combined shader; vignette, HUD and menu draw AFTER the blit. All-zero = bypassed entirely.
- **THE RETRO RT IS `GL_NEAREST`, AND PIXELATE POINT-SAMPLES IT.** `sceneTap` box-filters the block
  (`PIX_BOX`) instead of keeping one pixel of four, which is a TRADE — the twinkle IS a hard edge
  crossing a pixel boundary. **Sub-pixel filter offsets snap under nearest**, so the chroma fringe's
  offset now snaps to whole BLOCKS or R/B smear a whole pixel apart.
- **THE UI NAMES BUTTONS, NEVER KEYS** (owner's call). Every prompt, crib and footer in the GAME shows the
  button that does the thing, DRAWN — `hud.Hint`, `hud.hintRow`/`hintRowAt`, and the `padFace`/`padDpad`/
  `padBumper`/`padMenu` pictograms ported from zig-diablo's `hudx`. There is no keyboard caption anywhere and
  no pad-vs-keyboard branch: one strip, whether a pad is plugged in or not, so there is no second caption to
  keep in step and no branch that can show the wrong half. Keys still work; they are simply not what the
  chrome talks about. The glyphs live in `hud.zig` and not `uiart.zig` for one reason: a face button is a
  LETTER, and that file is the only path to draw text. **The EDITOR is the one exception and it is not this
  UI** — a mouse-and-keyboard authoring tool with no pad bindings at all, so its own crib names keys.
- **A BUTTON IS NAMED ONCE** — `hud.BTN_INTERACT`/`BTN_CONFIRM`/`BTN_BACK`/`BTN_QUICK`. `game.zig` binds off
  them and every crib draws off them, so a rebind moves the caption and the press together.
- **THE CURSOR IS A LEADING BAR, AND IT IS THE ONLY THING THAT MARKS A ROW** (owner's call). `uiart.caret` is
  the one that draws it and `uiart.rowHilite` lays it under the wash, so a list cannot grow a second kind of
  cursor. Every menu used to set a `>` glyph in the left margin ON TOP of the bar the wash was already
  drawing — one cursor said twice, in two places that had to agree, and a column of arrows down the card
  besides. A row too dim to take a wash (an empty slot, a refused option) draws the bar on its own at
  `CARET_DIM`: the cursor may never be invisible on the one row it is standing on, which is exactly the row
  whose reason you are trying to read. The `<` `>` PAIR ON A GAUGE stays — that is "this row adjusts", not
  "you are here".
- **All UI text goes through `hud.text/textW`**, in **Balthazar** (`assets/`, OFL; owner's pick). The
  atlas is ASCII-ONLY — a `·` or `—` renders as tofu. Exo and Tagesschrift are GONE; one face only.
- **SIZES COME FROM `hud`'s TYPE SCALE** (`TITLE`/`BODY`/`SMALL`/`HINT`/`TINY`, plus `MONO` for the editor's
  own readouts), never a literal at the call
  site; rows step by `hud.lineH(size)`. The atlas resolution must stay ABOVE the largest size drawn,
  and the drop shadow's offset scales with the size.
- **HUD colours are LITERAL screen values** — drawn after the retro blit, outside the scene shader, so
  the author-dark rule does not apply there.
- **AND THAT IS WHY THE CHROME FADES AS ONE PICTURE, NOT AS A LIST OF THINGS THAT EACH KNOW AN ALPHA**
  (`hud.beginChrome`/`endChrome`, `game.HUD_FADE_DUR`). Dying used to take the HUD off on one frame; it now
  goes out over 0.55 s, read off `hero.deathT` — the clock the YOU DIED card is already drawn from, so the two
  cannot disagree about when he died — and short of the card's own first beat, so the bars are leaving before
  the screen starts to dim. It is composited through a target because the alternative is threading a factor
  through every literal in `hud.zig` PLUS `uiart`'s rules and the `itemart` pictures in the cross, which are
  not this file's colours at all: one call site missed is a slot left solid over a HUD that has gone, which
  reads worse than the hard cut. The target is only taken WHILE a fade runs — at full chrome `beginChrome`
  refuses and every draw goes straight at the backbuffer as before. **The BANNER is not chrome** and is laid
  down after `endChrome`: a line the world is saying does not go out with the bars.
- **Prototype models/meshes are permanent** (CPU arrays stay attached and leak at exit — fine). Don't
  `unloadModel` them. TERRAIN TILES are the one exception, and cost two crashes:
  - **`gfx`'s mesh allocator MUST be `raw_c_allocator`, not `c_allocator`.** raylib frees mesh CPU
    arrays with libc `free()`, and `std.heap.c_allocator` does not hand out malloc pointers on Windows
    — freeing one frees an interior pointer. Heap corruption, surfacing as `0xC0000374` with no stack.
  - **`rl.unloadModel` UNLOADS THE MATERIAL'S SHADER** — which on a terrain tile is the SCENE shader.
    Go through `env.unloadTerrain`, which points the material at raylib's default shader first.
- **GLSL RESERVED WORDS ARE NOT ONLY THE OBVIOUS ONES.** A local named `patch` compiled everywhere the
  author tested and failed on Intel, which enforces it at `#version 330`. `layout`, `subroutine` and
  friends are the same trap, and a scene shader that fails to compile is a hard startup panic.
- **raylib's `SetSoundPan` IS THE LEFT CHANNEL'S GAIN, not a position.** The mixer is
  `left = pan; right = 1 - pan`, so **`pan = 1.0` is hard LEFT**. `audio.panFor` is the only place the
  sign is decided and a test pins it. The pan law is `0.5·x·(3 − x²)`, so a hard-panned sound is
  ~3.2 dB louder in its own ear than a centred one.
- **`master` NORMALIZES each voice** (`norm`), so a layer's `amp` sets its BALANCE inside the voice and
  only `BANK.gain` sets how loud it is. **THE FIGHT IS ONE BAND** — combat rows above `BATTLE_FLOOR`
  (0.34) are pulled geometrically toward the soft end, halving the spread in dB. Retune by moving the
  FLOOR, not by pushing one row back up; a test pins the ratio and the orderings.
- **THE VOLUME IS RESERVED FOR WHAT IS ABOUT TO HIT YOU** (owner's call). A creature's committed arrival
  outranks its own movement noise — lunge over hop, slam over step, stab over wingbeat, swing over creak —
  and the tells sit past the midpoint of the band. **TEXTURE GOES AT OR UNDER THE FLOOR**, which is what
  takes it out of the band entirely: hops, the wingbeat, the idle creak, the whirl. A second test pins both
  halves, in PAIRS, so each is that creature's own decision rather than a comparison across two sizes.
- **AND TEXTURE IS THINNED IN COUNT, NOT JUST IN LEVEL** — `leechfly.DRINK_EVERY`, `rooted.CREAK_EVERY`, and
  the hiss the brood mother no longer spends on laying a sac. A voice that repeats through a hold is not an
  event however quiet it is. The one cadence that MAY NOT be thinned is `leechfly.WHINE_EVERY`: the take is
  cut a hair longer than its own period so consecutive ones overlap, and gapping it is the helicopter.
- **THE FAMILY LEVEL IS `TRIM_COMBAT` (0.46), NOT THE FLOOR** — the floor moves only the `battle()` band,
  where the trim reaches the literal-gain rows too (the swings, the chant, the draw). Whole-family moves go
  there. **And the fight is rolled off the top** (`COMBAT_TREBLE`, one pole at bake in `bakeRow`, UNDER the
  player's rack so a dial still sits on top of it): the fizz on a struck edge is what makes a busy fight
  tiring, and the body of every one of these voices is well below the cut.
- **The sound filter rack is BAKE-TIME** — raylib cannot filter a playing voice, but every
  voice is synthesized, so a dial re-renders that family (coalesced by `FX_SETTLE`). A bake STOPS
  every take before freeing any of it. **IT LIVES IN THE EDITOR, beside the JUKEBOX** (`editor.rackPanel`,
  the `.jukebox` modal) and not in the game's debug menu: it is an authoring tool rather than a setting, and
  the one place a voice can be played on demand is the list next to it. Its eleven dials end in the EQ pair
  (`AF_BASS`, `AF_PRESENCE`), which are applied LAST — the tone of the result, not another thing to distort.
  The RETRO rack stays in the menu; that one is a LOOK the player picks.
- **Never bulk-edit source through PowerShell** `Get-Content`/`Set-Content`: em dashes mojibake and a
  BOM appears. Use the Edit tool.

## Gaps

THE BONE KNIGHT HAS NO FIGHTING STANCE. `poseUpper` sets no leg pose at all while he is standing, so
`hero.legChain` gives him straight legs and feet at their rest offsets: no knee flex, no foot stagger, no
weight on the back foot, and none of it changes through either stroke. `legBrace` only drops the pelvis. It
cannot be bolted on AFTER `legChain` — that is the hand that levels the ankle against the `SolePatch`, so an
override there un-levels the foot (FEET DO NOT SINK) — and a bespoke walk is forbidden outright. The stance
has to go THROUGH `legChain`, which is the shared humanoid one, so it is every creature's change, not his.

AND HIS SWORD ARM CARRIES A LONG TAIL OF GRIP. The blade now stands upright behind his own pauldron rather
than lying diagonally across his back, but 0.24·H of leather hangs BELOW the fist — 1.27 m at scale — so from
behind the pommel reads as a second stick past his hip. The mesh's grip length, not the carry angles.

THE BLADE IS A PLANK BY PROPORTION: `SW_HALF_W` 0.032·H is 0.34 m across on a 2.86 m edge, about 8:1 where a
greatsword is nearer 20:1. It is also the cleave's hurt radius, so narrowing it is a mechanical change as well
as a mesh one.

THE BONE KNIGHT IS A BOSS WITH NO BOSS FURNITURE: no arena, no fog gate, no health bar across the bottom, no
`worldfmt` boss record (see `inCombat`'s note), and **no `knight_*` voice family** — he borrows the ogre's
step, slam, heave and roar and the skeletons' hurt and die. And a DOWNED knight's collider is still the circle at his feet, so the three
metres of body lying behind them can be walked through — a capsule for a floored creature is the fix, and
nothing else in the game needs one yet.

THE NECROMANCER HAS NO `necro_*` VOICE FAMILY — it borrows the shade's, the wand's and the skeletons', the Bone
Knight's own gap one creature along. Nothing RESISTS cold on the hero's side either: the sheet shows all four at
0% and there is no cold-warding item, so the game's one cold source lands on him unmitigated by construction.
And nothing raises a body but this creature, so `foe.rekindle` has exactly two callers.

No criticals, guard counter, or AR × motion-value damage (flat constants
today). THE JUMP EXISTS but nothing hangs off it yet: no jump ATTACK (the one thing ER bills stamina for), no
fall damage at any height, and no creature's move misses him for being over it — a sweep you jump is a sweep
that still lands, because a per-move height is authored at each `toImpact` the way a parry window is. SOULS BUY LEVELS AND NOTHING ELSE — there is no merchant. The PASSIVE TREE is the basic version: 21
nodes, three arms of seven, no respec, no jewel sockets, and no second grant on a node. Twelve of the
twenty-one are attribute nodes — four an arm — and four of the seven attributes are still inert (the sheet
says so). The BINDING RING is the only wearable
that does anything and it is worn by being CARRIED — there is no ring slot, because there is no equip system
under one. POISON is the only status effect, it is the HERO's alone (nothing applies one to a foe, and no foe
reads one), and nothing RESISTS it yet — the sporeling cap's ward still grants CHAOS resistance, which since
the venom became poison protects against nothing in the world. THE SEVEN NEWEST ITEMS (fire tallow,
thundercrock, cracked rune, toadflesh broth, fang dirk, grave warbow, quilted gambeson) are registered and
the four tools WORK, but nothing PLACES any of them — no chest holds one and no map op drops one. The crock
lands with no burst FX yet, and the tallowed blade shows nothing on the sword while it runs. The parry exists but has no RIPOSTE behind it — a caught blow buys a stagger and the ordinary punish,
not a critical. Four creatures carry parry windows; the archers, the kobolds and the shades have none yet, and
the broodlings are out on purpose. No foot IK — `rx(bodyPitch)` rotates about the WORLD ORIGIN, so a deep lean levers a
forward-swung foot down and feet clip a few cm on slopes. The roll has front-loaded i-frames but no
collision. One leg-cycle is reused across run and sprint. Nothing scales a cast — spell damage is flat
constants like everything else. Elevation exists but nothing is authored with
it: no falling, terrain casts no shadows, painted water is one level plane.

**The script layer is foundations only.** THE EDITOR CANNOT AUTHOR ANY OF IT YET — no Triggers layer, no NPC
unit brush; triggers, dialogs and `npc:` records are hand-written in the `.world` file, and the editor
round-trips them untouched because the writer emits them off the same tables. One `NpcKind` (`wanderer`), so a
second person in this world is a second head variant away rather than a new creature. No quest log and no
journal: what a trigger has to say it says through `text` or through a conversation. A roamer wanders inside a
radius about its post; there are no authored patrol points. `deaths brood_sac` is billed off the brood's own
`bursts` rather than a `justDied` edge on the sac.
