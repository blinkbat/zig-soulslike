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
- **REACTIONS ARE HUGE.** A flinch or stagger must be big and obvious, never a subtle lean.
- **FLESH IS ROUND.** Organic mass = `addBlob`/`addCapsule`; `addCube`/`addBox` is for iron, blades,
  cloth, masonry. Bare `addCylinder` leaves an open cut-pipe end — those rims and boxes are what read
  as BLOCKY however good the animation on top.
- **BIG BODIES HINGE AT THE WAIST, LEGS STAY PLANTED.** Route lean through SPINE/CHEST and leave the
  pelvis near-upright (`ogre.PELVIS_SHARE`); lean at the ROOT rotates the legs and reads as lurching.
  Braces take up in the knees, they don't squat.
- **WABI-SABI is the house style for ALL art.** Uneven sizes, asymmetry, leans, gaps. Author the
  variation in with a seeded `mathx.Rng` so builds stay deterministic. When a model or anim reads
  "dumb"/fake it is almost always too REGULAR. Cosmetic only — mechanics stay exact.
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
| `worldfmt.zig` | THE MAP FORMAT — op vocabulary, zone/foe tables, one comptime field table driving writer and parser |
| `env.zig` | THE WORLD — terrain, op replay, `coverField`, uniform grid, cullers, occluder fade, lights |
| `editor.zig` | THE EDITOR (Menu > Editor), layered StarEdit-style; biggest file, next split candidate |
| `objview.zig` | object viewer + the JUKEBOX (sound auditioning) |
| `props.zig` | prop VOCABULARY + the `INFO` table (one row per kind); `displayName`/`group`/`stock` are exhaustive switches |
| `prop*.zig` | the meshes by family — `propart` (palette + weathering), `propruins`, `propbuild`, `propvillage`, `proprock`, `propwood`, `propflora`, `propfx` |
| `foe.zig` | THE FOE STANDARD — shared contract, `Blade`/`strike`/`weaponReaches`/`Blow`, `Trail` ribbon, particles, `Leash`, group plumbing |
| `frog.zig` | gaping toad + `Knot` |
| `archer.zig` | skeletal archer + `Line`; kite-only, arrows that stick and fade |
| `ogre.zig` | one-eyed ogre + `Grief`; 24 bones, high poise, overhead slam + side swipe, never strafes |
| `kobold.zig` | kobold warband + `Warband` — three roles of one creature (berserker/priest/slinger); the priest is why they are one group |
| `brood.zig` | brood mother, sacs, broodlings + `Brood`; guard not hunter, acid POOLS are the weapon |
| `warrior.zig` | skeletal warriors + `Muster` — shieldman (blocks, guard-breaks to one knee) and greatsword (uninterruptible slam) |
| `combat.zig` | `Vitals` (HP + two-tier stagger + regen + death), `Stamina`, `Focus`, `Regen`, guarding rules, `HitOutcome`, `Elem`/`Resists`. THE place to retune feel |
| `stats.zig` | the character sheet — seven attributes and the curves that make the bars |
| `item.zig` | item vocabulary, `Use`, the `Bag` |
| `chest.zig` | openable boxes; contents read off the placing op (`Op.loot`) |
| `rest.zig` | bonfire + campfire grace; `isRestKind` is the one predicate |
| `hud.zig` | ER HUD + the ONLY path to draw/measure text |
| `ui.zig` | editor widget kit; `Ctx.anyHot` gates world clicks next frame |
| `uiart.zig` | chrome DRESSING shared by hud/menu/book/ui |
| `itemart.zig` | pictures of things — armaments and bag items as objects, sized by the caller |
| `icons.zig` | editor glyph set, drawn from primitives (vector, not an atlas) |
| `book.zig` | THE CHARACTER BOOK (pad START) — equipment / inventory / stats |
| `menu.zig` | pause/debug menu, sound levels, retro + sound filter racks |
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
- **Reuse the behaviour.** `tryHit` is `if (foe.strike(...)) |s| { own FX; react on s.reaction }` —
  the swept test, one-hit latch and damage live in `foe.strike`.
- **Build vitals with `combat.Vitals.initFoe`**, never `init` — that is the slow foe regen schedule.
- **`justDied` is a ONE-FRAME flag.** Reset at the TOP of `update`, set in `enterDeath`, apply the
  blade at the END. Applying it externally without the reset latches a nonstop rumble/shake.
- **A CORPSE IS NOT A COLLIDER.** `alive()` stays true through the collapse and dissipation, so every
  collision site asks `foe.corporeal` (`alive() and !dying()`) instead.
- **Group + register.** Wrap instances in a `Group` exposing `anyDied`/`totalHits`/`aliveCount`; its
  `reset` and `draw` are ONE-LINE DELEGATES to `foe.resetGroup`/`foe.drawGroup`. The draw's
  `setFlash(0)` tail is what a fourth copy would forget.
- **A multi-kind group answers for its own members** — `kind = null` in `FOE_GROUPS`, each member
  exposes `kind()`. A group with anything else on the field (sacs, acid) exposes `clear()`.
- **Anything the map can post is a `wf.FoeKind`, APPENDED never inserted** (editor unit brushes are
  pinned to that enum's order at comptime), plus `foeName`, a `unitTips` line, a `unitIcons` glyph and
  a `foeSwatch`. Several kinds of one creature go in as a CONTIGUOUS RUN, pinned at comptime.

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
- **TWO OF THE FOUR ARE LIVE** — FIRE (hero's fire arrow, kobold sling clump) and CHAOS (brood spit
  and pools, hero's chaos bolt). Cold and lightning have no source yet.
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

**R1/R2 (and L1) BELONG TO THE ARM, NOT THE WEAPON.** The attack buttons are read as buttons and
routed by which armament is in that hand, so neither weapon can swallow the other's press. Swaps:
D-pad Right / Q = sword ↔ bow; D-pad Left / F = shield ↔ wand; D-pad Up / Y = plain ↔ fire arrow.

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
- **BILLED IN FP AND NOTHING ELSE** — `SPELL_FP` 12 of 60, five casts to a grace. An empty stamina bar
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
- **ALL CHAOS, NO PHYSICAL** — `SPELL_HIT` 24 chaos, poise 14, stance 6. Chaos is the most-resisted
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
- **THE OCCLUDER FADE** (`env.markOccluders`): a prop that `fades` between lens and hero goes thin,
  keyed to how much of him it hides, MEASURED AGAINST THE COLLIDERS not the bound. Three rules keep it
  from reading as a switch: the geometry sets a TARGET and time walks you there (`OCCL_IN` 0.16 s,
  `OCCL_OUT` 0.34 s — out is slower); it stops being in the way over a BAND not a plane
  (`OCCL_DEPTH_BAND`); and `OCCL_MAX` counts what is in flight, both directions.

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
- **Guard or CAST:** hold L1/LB or RMB. The button belongs to the HAND, not the shield.
- **Aim:** hold L2, or RMB with the bow out (free to take it because the bow already took the shield).
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
- **Depth z-fighting:** `rlSetClipPlanes(0.2, 320)` at startup. The ground sits a hair above y=0
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
- **The player's sound filter rack is BAKE-TIME** — raylib cannot filter a playing voice, but every
  voice is synthesized, so a dial re-renders that family (coalesced by `FX_SETTLE`). A bake STOPS
  every take before freeing any of it.
- **Never bulk-edit source through PowerShell** `Get-Content`/`Set-Content`: em dashes mojibake and a
  BOM appears. Use the Edit tool.

## Gaps

No criticals, guard counter, parry, jump, status buildup, or AR × motion-value damage (flat constants
today). No foot IK — `rx(bodyPitch)` rotates about the WORLD ORIGIN, so a deep lean levers a
forward-swung foot down and feet clip a few cm on slopes. The roll has front-loaded i-frames but no
collision. One leg-cycle is reused across run and sprint. Sorcery is ONE spell deep and nothing scales a
cast. Elevation exists but nothing is authored with
it: no falling, terrain casts no shadows, painted water is one level plane.
