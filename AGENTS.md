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
| `game.zig` | window/loop, input, camera-relative movement, render orchestration, combat-beat feedback, YOU DIED |
| `hero.zig` | THE HERO — FK skeleton, every animation, swept blade capsule, the guard, the bow, the wand. Start here |
| `camera.zig` | over-the-shoulder orbit rig, ground basis, trauma shake (live-loop only, so `--shot` stays deterministic) |
| `gfx.zig` | mesh `Builder`, scene shader, shadow depth pass, `Sky`, `Vignette`, `Mat` surface materials |
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
| `shade.zig` | shades + `Haunt`; legless, hovers, 17 bones of its own. The one thing that drains FOCUS, the one thing that TELEPORTS |
| `leechfly.zig` | THE FIRST FLYER + `Swarm`; 15 bones, never lands. Drinks his HP through a beak and heals off what it takes, and ZOOMS out of sword reach |
| `rooted.zig` | THE TREE THAT ISN'T + `Grove`; a snag-mimic fixture — eyes open outside its reach, three limb strikes (slam/sweep/hook-drag), never moves |
| `shroom.zig` | the sporeling + `Cluster`; a squat mushroom that FLINGS itself and bursts a lingering spore cloud that POISONS (buildup, never damage). Sometimes it TRIPS instead — same gather, longer opening |
| `combat.zig` | `Vitals` (HP + two-tier stagger + regen + death), `Stamina`, `Focus`, `Regen`, guarding rules, `HitOutcome`, `Elem`/`Resists`. THE place to retune feel |
| `stats.zig` | the character sheet — seven attributes and the curves that make the bars |
| `item.zig` | item vocabulary, `Use`, the `Bag` |
| `chest.zig` | openable boxes; contents read off the placing op (`Op.loot`) |
| `rest.zig` | bonfire + campfire grace; `isRestKind` is the one predicate |
| `souls.zig` | THE DROP — what a death leaves on the ground, the gold bloom it stands as, and the walk back for it |
| `hud.zig` | ER HUD, the PAD-GLYPH kit every prompt and crib is drawn with, and the ONLY path to draw/measure text |
| `ui.zig` | editor widget kit; `Ctx.anyHot` gates world clicks next frame |
| `uiart.zig` | chrome DRESSING shared by hud/menu/book/ui |
| `itemart.zig` | pictures of things — armaments and bag items as objects, sized by the caller |
| `icons.zig` | editor glyph set, drawn from primitives (vector, not an atlas) |
| `book.zig` | THE CHARACTER BOOK (pad START) — a Diablo paper doll + ten quick sockets, the bag, the sheet |
| `menu.zig` | pause/debug menu, sound LEVELS, and the retro filter rack. The SOUND filter rack is not here — it is the editor's (`editor.rackPanel`) |
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
  is over and it dissipates over `DISS_DUR` into grace motes rising and flakes of itself falling. The two
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
- **A multi-kind group answers for its own members** — `kind = null` in `FOE_GROUPS`, each member
  exposes `kind()`. A group with anything else on the field (sacs, acid) exposes `clear()`.
- **Anything the map can post is a `wf.FoeKind`, APPENDED never inserted** (editor unit brushes are
  pinned to that enum's order at comptime), plus `foeName`, a `unitTips` line, a `unitIcons` glyph and
  a `foeSwatch`. Several kinds of one creature go in as a CONTIGUOUS RUN, pinned at comptime.

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
- **THE WINDOW AND THE ANIMATION ARE TWO CLOCKS** (`parryLive` vs `PARRY_DUR`). The catch is open for ~0.15 s at
  the front; the shove plays for a third of a second after it shuts, and `canGuard` refuses the whole time — so
  a mistimed parry leaves him with no shield either, whether or not he was holding one. That tail IS the price.
- **THE ATTACK ALWAYS DIES; THE HEAVY STUN IS EARNED** (owner's "may heavy stun them"). `combat.PARRY_HIT` is
  STANCE and nothing else — no damage, because a parry has never been damage, and no poise, so a catch can
  never resolve as a flinch: it breaks the stance or it does not. Whether a catch is a stumble or a punish
  window is the same bar the sword has been chipping all fight, not a dice roll.
- **THE CREATURE READS THE SHIELD, IT NEVER REACHES FOR IT** (`foe.Parry`, stamped by `game.markParry` exactly
  as `markSight` stamps the eyes). Each MOVE answers for its own frames and its own reach (`ogre.parryable`):
  only the move knows where its head is, and a slam you rolled clear of is not one a shield six metres off can
  touch. **FOUR CREATURES CARRY WINDOWS** — all four of the ogre's blows (slam, swipe, return, drive — a held
  slam tell moves nothing, since the window reads the DROP), both skeletal warriors' three strokes
  (mace, slam, lunge), the brood mother's bite and the toad's leap. Adding one is a `parry` field, a `toImpact`,
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
  did. `Flasks` still owns their CHARGES, because those come back at a grace where everything else comes out
  of the bag — `combat.quickCount` is that split, ONE copy, asked by the HUD off the live game and by the
  book off its `View`.
- **CYCLE STAMPS `flasks.sel`, it does not cycle it** (`hero.cycleQuick` → `syncFlask`). The draught, the HUD
  tint and the charge count all keep reading the one field they always read, and only the bar decides what
  is up. Nothing calls `Flasks.cycle` any more.
- **A REMOVAL LEAVES ITS HOLE.** The bar is stepped by muscle memory mid-fight; a list that compacts under
  you every time you drop something is one you cannot learn.
- **EACH BAR ENTRY IS ITS OWN SOCKET ON THE PAGE** — two rows of five on the paper doll, and Confirm on one
  puts a kind in THAT socket (`combat.Quick.put`, which moves a kind already elsewhere on the bar rather
  than copying it). The rows are FILTERED to what he actually carries (`quickOffered`) and carry an empty
  row, so a kind's ordinal is not its row and `pickIndexOf` counts it out the way `candidates` builds it.

### Souls — the drop, and the ring that refuses it

**WHAT YOU WERE CARRYING IS ON THE GROUND WHERE YOU DIED** (`souls.zig`) — DS's bloodstain and ER's rune drop,
which are one mechanic under two names. Everything comes off him on the frame he DIES rather than at the
respawn, so the spill plays under the YOU DIED card, which is the one moment nothing else is playing.

- **THERE IS EXACTLY ONE.** A second death overwrites the first and the first is gone for good. That is not a
  storage decision, it is THE mechanic: a list of drops would quietly delete the whole risk.
- **NOTHING ELSE SPENDS IT.** No timer, no decay, no despawn on distance — only picking it up or dying again.
  A death RE-HOMES the field (`game.resetFoes`) and must not touch the drop; only a change of MAP clears it,
  which is `game.armScript` and nowhere else.
- **AND RETRIEVAL IS INSTANT** (owner's call). No committed action and no animation on the man: the runes are
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
- **THE PROMPT IS FIRST IN `game.reachable`** and its ring is the smallest of the four: you can die at a grace,
  and on the frame you walk back in there is exactly one thing you came for. One press clears it and the fire
  is offered again.

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
- **A GRACE CURES IT** (`hero.makeWhole`), and a death is a return to one.
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
- **ONE AND A HALF OF THE FOUR ARE LIVE** — FIRE (hero's fire arrow, kobold sling clump) and CHAOS, which
  is now the WAND'S ALONE (the bolt and the roots' grip). Cold and lightning have no source yet, and nothing
  in the world deals chaos AT the hero since the brood's venom and the sporeling's spores became POISON.
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

- **NOTHING GRANTS THE HERO ANY YET, AND THE SHEET SAYS SO** — the book's STATS page shows all four at
  0%. `makeWhole` CARRIES RESISTANCES ACROSS a grace: they are what he is, not a meter to refill.

### The character sheet (`stats.zig`)

Seven attributes; `hpFor`/`fpFor`/`staminaFor` turn Vitality/Mind/Endurance into the bars at ER's
documented soft caps. **The starting sheet reproduces the tuned bars exactly** — every attribute
starts at 15, which is where the curves yield 70 HP / 60 FP / 105 stamina, so `hero.HP_MAX`,
`combat.FP_MAX` and `combat.STAM_MAX` are DERIVED and a test pins all three. **The bars take their
size from the sheet in one place** — `hero.makeWhole`. The four attributes nothing reads yet say so on
their own row.

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
  grace. The quiver is checked BEFORE stamina is charged. The SELECTED kind is what flies, empty or
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
- **BILLED IN FP AND NOTHING ELSE** — `BOLT_FP` 12 of 60, five casts to a grace. An empty stamina bar
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
  (0.55) keeps the middle solid. **Hard vs soft edges are a property of the MATERIAL**
  (`Soil.hardEdge`, stone only), pinned to the shader's `soilHard` by a comptime assert.
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
    do: text Someone is sitting at the grace.
  ```

  **`npc:` RECORDS ARE APPENDED, NEVER INSERTED** — `near npc=0` is an INDEX into that table (SC1's own
  spawn-index form, and bg2's), so putting a new person above an existing one silently repoints every
  condition after it. `foe:` and `wf.FoeKind` have the same rule for the same reason.

  Conditions: `always`, `never`, `flag N=0|1`, `counter N <cmp> n`, `timer N=done|running`,
  `elapsed <cmp> secs`, `region x z x1 z1`, `near npc=i r=m`, `talked dlgId`, `deaths foeKind <cmp> n`,
  `alive foeKind <cmp> n`. Actions: `dialog dlgId`, `text …`, `flag N=0|1|flip`,
  `counter N set|add|sub n`, `timer N=secs`, `wait secs`, `preserve`. `<cmp>` is `<` `<=` `=` `>=` `>`.

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
- **EVERYTHING THINS EXCEPT WHAT SAYS `solid`** — architecture, cliffs, the water sheet, the grace (its
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
- **ONLY AFTER `LEASH_CALM` (4.5 s) WITH NO BLOW GIVEN OR TAKEN**, and only with the hero out of its
  ring — a foe with him in its face has no business turning round.
- **A WALK HOME IS NOT BLIND** — step back inside the ring, or land one blow, and it turns on the spot.
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
- **Lock-on:** R3 / middle mouse; a flick cycles. Suspended entirely while aiming. Two ER exceptions:
  a hold-B sprint faces TRAVEL, and an attack's recovery tail re-squares (`ATK_RETRACK`).
  **YOU CANNOT FIX ON WHAT YOU CANNOT SEE** — a foe behind a wall is not offered (`game.canSee`), but
  a HELD lock fades rather than switching (`LOCK_BLIND_HOLD` 1.1 s), or a pillar crossing the line
  mid-circle throws the camera off.
- Reserved, matching ER: Cross/A = jump.

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
- **Sun + shadows are ONE source** (`gfx.SUN_DIR`) feeding both the shader and the shadow camera.
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
- **`gfx.Mat` is APPEND-ONLY** — the shader hard-codes 9 for water and 10 for marble; comptime asserts
  guard both.
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
- **All UI text goes through `hud.text/textW`**, in **Balthazar** (`assets/`, OFL; owner's pick). The
  atlas is ASCII-ONLY — a `·` or `—` renders as tofu. Exo and Tagesschrift are GONE; one face only.
- **SIZES COME FROM `hud`'s TYPE SCALE** (`TITLE`/`BODY`/`SMALL`/`HINT`), never a literal at the call
  site; rows step by `hud.lineH(size)`. The atlas resolution must stay ABOVE the largest size drawn,
  and the drop shadow's offset scales with the size.
- **HUD colours are LITERAL screen values** — drawn after the retro blit, outside the scene shader, so
  the author-dark rule does not apply there.
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

No criticals, guard counter, jump, or AR × motion-value damage (flat constants
today). SOULS DROP AND ARE RECLAIMED but nothing SPENDS them yet: there is no levelling and no merchant, so
the counter is a score with a real risk attached and nothing to buy. The BINDING RING is the only wearable
that does anything and it is worn by being CARRIED — there is no ring slot, because there is no equip system
under one. POISON is the only status effect, it is the HERO's alone (nothing applies one to a foe, and no foe
reads one), and nothing RESISTS it yet — the sporeling cap's ward still grants CHAOS resistance, which since
the venom became poison protects against nothing in the world. The parry exists but has no RIPOSTE behind it — a caught blow buys a stagger and the ordinary punish,
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
