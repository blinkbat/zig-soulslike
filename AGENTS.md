# AGENTS.md — zig-soulslike

A third-person **soulslike** prototype in native **Zig 0.14.1 + raylib**. Founded on the
sibling `../zig-rts` rendering engine (procedural-mesh `Builder`, single-sun shadow-map
pipeline, Exo HUD), which itself descends from `../zig-diablo`.

Keep this file lean. Prefer no comments in code; write succinct ones for novel/edge cases.
Reuse existing helpers before adding new code. Don't make ad-hoc product/design decisions —
ask. The owner (David) drives the design; implement what's asked and nothing extra.

**FEEL RULES (owner's law, non-negotiable):**
- **NO HITSTOP. EVER.** No freeze-frames, no time-dilation on impact, no dt zeroing.
  Impact weight is carried by camera shake + rumble + blood/flash FX + the huge reaction
  anims — never by stealing time from the player.
- **ZERO INPUT LAG.** The stick maps STRAIGHT to ground speed every frame (light tilt =
  walk, full tilt = run, keyboard = immediate run; no run-unlock hold, no windup gates).
  Posture/gait blends may smooth the VISUALS only, and only very fast (~0.1s max) —
  movement mechanics answer the input the same frame it happens.

**WABI-SABI is the house style for ALL art.** Nothing organic is machined to uniform
perfection — gaits, the dodge roll, creatures, teeth, flora, the prop scatter all earn their
life from deliberate IMPERFECTION: uneven sizes, asymmetry, leans, gaps, the odd broken or
oversized piece, magnitudes drifting piece to piece. Author the variation IN with a seeded
`mathx.Rng` (so builds stay deterministic) instead of laying elements out in clean rows or
mirrored pairs. When a model or anim reads "dumb"/fake, it's almost always too REGULAR — rough
it up. Wabi-sabi is COSMETIC only: mechanics stay exact (the roll's body is imperfect, but its
distance/heading/timing are identical every time).

## What exists (first demo = locomotion + camera)

A convincingly **human** hero that **walks / runs / sprints / dodge-rolls** and **swings a
sword** (R1 light slash / R2 heavy overhead, kinetic-chain sequenced, blade hit-capsule
scaffolding), under a **third-person over-the-shoulder camera**, in a **lit 3D world with
cast shadows**: a golden-hour plain (warm low sun vs cool slate sky, procedural cloud
deck, distance haze, vignette) dressed as a fallen kingdom — colonnade avenue, gate arch,
walls, dead trees, graves, war banners, a statue, an emissive grace ember, and colossal
hazed horizon ruins. A **knot of gaping toads** hunts the hero (hop/lunge/chomp AI), with
**ER lock-on**, and a full **combat layer**: HP + a two-tier poise/stance stagger (light
flinch → heavy stance-break) + death, both sides (see `combat.zig` and **`docs/ELDEN_RING.md`**,
the systems reference). No stamina, i-frames, criticals, guarding, or jump yet.
The bar for "human" is anatomy (real segment proportions) + real gaits, not polygon count.

## Build & verify

- `zig` is NOT on PATH. Build with `build.cmd` (debug) / `build-release.cmd`; the vendored
  toolchain is `..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe` (shared with the siblings).
- `zig build test` runs unit tests.
- Verify rendering/animation changes by RUNNING `zig-out\bin\zig-soulslike.exe --shot` (or
  `shot.cmd`) and INSPECTING the PNGs in `shots\`. `--shot` HIDES the window (headless):
  it scripts a −Z walk→run→sprint and a dodge roll, capturing side/front/back/3-quarter
  angles at each speed. Never claim a visual change works without a shot. `shots\` is
  gitignored. Do NOT launch the interactive window to "check" — use `--shot`; the owner
  launches the real game themselves.
- **Framing is part of the test.** Before tuning an animation from a shot, confirm the camera
  actually SHOWS the moving part. A mis-framed angle (e.g. the SWORD arm hidden behind the
  torso — what yaw 270 did to the light slash) means you're tuning a swing you can't see, and
  every knob after that is guesswork. If a shot looks off, suspect the CAMERA first
  (yaw/pitch/dist) and capture the TRUE contact frame, not an arbitrary mid-point; fix the
  framing, THEN judge the anim. Diagnose bad shots EARLY — don't burn iterations on them.
- Don't commit, push, or create branches unless explicitly asked.

## Module map

- `main.zig`   — entry; `--shot` = headless screenshot harness.
- `game.zig`   — window/loop, input (mouse + gamepad), camera-relative movement + facing,
                 dodge-roll trigger, render orchestration (sun depth pass → retro capture
                 → lit main pass → filter blit → vignette/HUD/menu crisp), sky, HUD,
                 combat-beat feedback wiring (rumble + camera shake + per-actor hit flash;
                 NO hitstop), the YOU DIED card (drawDeathOverlay + respawn fade), and
                 the `--shot` harness (which also captures filter + menu verification shots).
- `menu.zig`   — the pause/debug menu (OPEN AT LAUNCH: Continue / Debug / Quit). Debug
                 holds Stats / Wireframe / Time Scale and the Retro Filters slider list
                 (15 filters + presets), all driving gfx.Retro / loop toggles. Inspired by
                 ../crawler's pause -> Debug -> Retro Filters tree.
- `hero.zig`   — THE HERO. Anthropometric FK skeleton + every animation (idle/walk/run/
                 sprint/roll/attacks, plus the locked-on STRAFE/BACKPEDAL footing: crossing
                 grapevine sidesteps + a time-reversed walk) + the blade hit capsule
                 (souls-style: rides the SWORD bone's dummy points, active only in the
                 strike's TAE-like window, endpoints swept frame-to-frame, FAT on purpose —
                 vertical forgiveness so the level swipe lands on low/tall foes) + the swing
                 trail ribbon. The light slash is a REAL cut — the HORIZONTAL pair (sabre
                 Cuts III/IV, Roworth 1798 / kendo dō-giri), a LEVEL swipe: blade riding the
                 OUTER EDGE of the arc for the whole hit window (owner's law: level +
                 outward, never a dirt-stab, never hilt-first) — see the CUT MECHANICS note
                 above the AL_* block. Start here for how the character moves.
- `camera.zig` — third-person over-the-shoulder orbit rig (yaw + clamped pitch, zoom,
                 shoulder offset, `recenter`), the camera-relative ground basis, and the
                 trauma-based impact shake (tickShake is live-loop only, so --shot stays
                 deterministic).
- `gfx.zig`    — scene shader (warm hard sun + cast shadows + hemisphere ambient + rim
                 light on non-terrain + sun-banked distance haze + gamma/dither + a flora
                 wind term gated by `windAmt`/`setWind` + the per-actor `hitFlash` uniform
                 + SURFACE MATERIALS: every Builder mesh carries surface-anchored UVs and
                 a `gfx.Mat` id in texcoords2, and matAlbedo() textures it procedurally —
                 stone/wood/cloth/steel/leather/skin/hide/plant, value-only, ±20% max, so
                 patterns stick to animated bones and NOTHING reads gaudy), the sun
                 shadow-map depth pass, the mesh `Builder` (setMat switches material per
                 shape), the fullscreen `Sky` shader
                 (gradient + sun aureole/disc + fbm cloud deck; ray from gl_FragCoord —
                 fragTexCoord is CONSTANT for drawRectangle), and the `Vignette` overlay.
                 Adapted from zig-rts by REMOVING fog-of-war (a soulslike is fully lit).
- `env.zig`    — procedural ground plane (extends far past the playable bounds so it
                 dissolves fully into haze) + a hand-placed prop layout: columns, gate
                 arch, walls, trees, graves, swords, banners, statue, grace ember,
                 horizon giants, and a seeded flora scatter (kind-indexed models, one
                 mesh each).
- `frog.zig`   — THE GAPING TOAD (first foe) + the `Knot` of them. Squash-&-stretch rig,
                 hop/lunge/chomp state machine, and the combat reactions (light flinch /
                 heavy stance-break stagger / death → a grace-gold mote DISSIPATION, never
                 a hard vanish). Landed blows read at the wound: contact-point blood burst,
                 knockback shove, and a blood-red body flash. Its attacks damage the hero;
                 the hero's swept blade damages it. Homes sit off the avenue so a straight
                 run won't wake them.
- `archer.zig` — THE SKELETAL ARCHER (second foe) + the `Line` of them. A BARE-BONES humanoid
                 (skull / ribcage / pelvis / bone-limbs + a bow) FOUNDED ON THE HERO RIG:
                 same anthropometry, and it walks/strafes on the HERO'S gait (see the humanoid
                 rule below), not a bespoke cycle. KITE-only AI (holds a range band, backs off
                 / closes, looses; never melees). Slowish, lightly-homing arrows that STICK
                 where they land + fade. One-and-done death (collapse → dissipate). Perched in
                 the ruins, waking as you advance. Arrows are a pool owned by `game.zig`.
- `ogre.zig`   — THE ONE-EYED OGRE (third foe) + the `Grief` (a lone, sorrowful giant). A GIANT
                 humanoid (~2x the hero), hunched + mis-proportioned, dragging a great knotted
                 CLUB, with ONE dull-amber glowing eye — a sad but scary figure. FOUNDED ON THE
                 HERO RIG like the archer (same 18-bone layout + `hero.advanceGait`/`legChain`
                 for the legs; the stride phase is fed a scale-corrected distance so the giant
                 doesn't skate). HIGH POISE (shrugs off single lights — sustained pressure
                 staggers it) + a lumbering approach into ONE attack for now: a big, readable
                 OVERHEAD CLUB SLAM (long windup tell → fast crash → long wide-open recovery),
                 front-arc crush only. Reactions are huge; death is a slow, weighty topple into
                 the grace-mote dissipation. More attacks to come — the state machine has room.
- `foe.zig`    — THE FOE STANDARD: the shared contract + behaviours every enemy plugs into, so
                 lock-on, floating HP bars, collision, the blade hit-test, and the combat beats
                 are written ONCE for all foes. Holds `Blade` (the hero's-swing data) and
                 `strike()` (swept hurt-sphere test + one-hit latch + damage) that frog + archer
                 `tryHit` both reuse. See its header contract + "Adding a foe" below.
- `combat.zig` — SHARED combat `Vitals`: HP + the two-tier Elden Ring stagger (poise → light
                 stun, stance → heavy stun) + regen + death. Pure logic, unit-tested; hero and
                 every foe embed one. THE place to retune damage/poise feel. See `docs/ELDEN_RING.md`.
- `collision.zig` — 2D XZ capsule/circle footprint collision (push-out); actors + world solids.
- `mathx.zig`  — ground-plane + vector/angle helpers (copied from zig-rts, extended).
- `hud.zig`    — UI text in Exo (assets/, OFL alongside); the ONLY path to draw/measure text.

## The hero rig (`hero.zig`)

- **Anatomy is real.** Bone lengths are fixed fractions of stature `H` (=1.8), from the
  Drillis & Contini (1966) segment table as tabulated in Winter, *Biomechanics and Motor
  Control of Human Movement*. This is why proportions read as human.
- **Forward kinematics.** A 17-bone skeleton (pelvis, spine, chest, neck, head, and 3-joint
  legs/arms). `pose()` chains a world matrix per bone ONCE per frame; `draw()` only replays
  the stored matrices. The sun depth pass and the lit pass both call `draw()`, so the cast
  shadow and lit silhouette always match. Bones are bare `rl.Mesh`es drawn with `drawMesh`
  through one material whose shader is swapped for the depth pass (`setShader`).
- **Matrix convention (critical):** raylib `MatrixMultiply(a, b)` applies **a FIRST, then
  b**. Local joint transform = `mul(animRot, translate(offset))`; world = `mul(local,
  parentWorld)`. Get this backwards and the skeleton explodes.
- **Gaits are real.** Walk uses normative sagittal hip/knee/ankle curves (Perry, *Gait
  Analysis* / Winter); run/sprint use Novacheck running kinematics (bigger ranges, flight
  phase). Curves are 8-sample tables interpolated by stride phase; the two legs are 50% out
  of phase. Phase is driven by DISTANCE travelled (never time) so feet never skate; stride
  LENGTH scales with speed so one leg-cycle reads at every pace.
- **HUMANOID ENEMIES REUSE THE HERO'S WALK/STRAFE ANIMS (owner's rule).** Any humanoid foe
  (the skeletal archer, and future ones) locomotes on the HERO's gait — the pub normative
  gait tables + `hero.legChain` (the walk cycle AND the locked-on strafe/backpedal footing)
  driven by a shared gait state (phase / moving / fwdB / latB) advanced by `hero.advanceGait`.
  Do NOT author a bespoke walk for a humanoid. Only the UPPER body / weapon work is per-enemy
  (e.g. the archer's draw+loose rides on top of the shared legs). The hero is the single
  source of humanoid locomotion; keep it that way so every human on screen moves as one.

### Animation art direction (the DESIRED look — honor it when retuning)

There is a full `ANIMATION ART DIRECTION` comment block at the top of the gait section in
`hero.zig`; keep it truthful. In short:

- **IDLE** — upright, still, alive: only a slow breathing bob. No limb motion.
- **WALK** — unhurried, grounded, calm. Near-upright (~3° lean). RESTRAINED arms (small
  swing, rear arm nearly straight — never both forearms out front, the "zombie arms" fail).
  LOW hip sway (no waddle). Clear heel→toe stride, readable knee bend, slight toe-out.
- **RUN** — low and aggressive. DEEP forward lean over a LOW centre of gravity (pelvis
  crouched), the WHOLE body pitched forward about the feet so the **COG leads the base**
  (driving, falling-forward). NORMAL pumping arms bent ~90° — explicitly NOT swept-back
  "naruto" arms (tried and rejected). Real flight phase via an up-only bounce.
- **SPRINT** — the run dialled up: even deeper forward tilt (near-diving), lower, longer,
  faster. "Falling forward and catching it."
- **ROLL** — a committed dodge in three beats: dive into a tight tuck, ONE forward somersault
  over ONE shoulder about a low ball centre (banked, limbs uneven, drifting a touch roll to
  roll — wabi-sabi, cosmetic only), then a spin-free rise to stance. The lunge is dead
  straight and the duration/distance/heading are exact every time. No float.

Blends: idle↔walk by a `moving` ease; walk↔run↔sprint by ground SPEED (`runB`/`sprintB`
chasing a short-eased speed); pose discontinuities (roll start/end) cross-fade ~0.09s and
the roll heading eases on fast — stances never snap, while mechanics stay instant.

## Adding a foe (the shared standard — `foe.zig`)

Enemies share ONE contract + behaviour set so the cross-cutting systems — lock-on, floating
HP bars, footprint collision, the hero's-blade hit test, the rumble/shake combat beats — are
written once and work for every foe. `foe.zig`'s header is the authoritative contract; the
frog and the archer are the two worked examples. To add a foe:

- **Satisfy the contract.** Expose `pos` + an embedded `combat.Vitals` (`vit`) + `hits` +
  `justDied`, and the accessors `alive/dying/staggered/airborne/bodyR/hurtRadius/centerWorld/
  lockPoint/topWorld/flashFrac` + `tryHit(foe.Blade)`.
- **Reuse the behaviour, don't re-roll it.** `tryHit` is
  `if (foe.strike(&vit, &hitLatch, centre, hurtR, blade)) |s| { own FX; react on s.reaction }`
  — the swept hit test, one-hit LATCH, and damage live in `foe.strike`; the foe only adds its
  own FX (blood, bone-clatter, …) + the enterStun/enterDeath transitions.
- **`justDied` is a ONE-FRAME flag.** Reset it at the TOP of `update`, set it in `enterDeath`,
  and apply the blade (call `tryHit`) at the END of `update`. Then the kill beat fires exactly
  once. (Applying the blade externally WITHOUT the reset latches it on → a nonstop rumble/
  screen-shake until you quit — the real bug that taught this rule. Mirror the frog exactly.)
- **Humanoids reuse the hero's walk/strafe** (see the hero-rig rule): `hero.advanceGait` +
  `hero.legChain` for the legs; only the upper body / weapon is bespoke. Never author a
  second walk cycle.
- **Group + register.** Wrap instances in a `Group` (a `Knot`/`Line`) exposing `anyDied` /
  `totalHits` / `aliveCount`; game.zig iterates groups generically (lock-on `FoeRef`,
  `drawFoeBars`, the collision + beat loops), so a new foe drops in with little or no new
  game.zig branching.

## Controls (`game.zig`)

Keyboard+mouse OR gamepad; the pad follows **Elden Ring's default layout**. (**ER** = Elden
Ring, the north-star reference, throughout this file.)

**WALK vs RUN (owner's definition — key locomotion FEEL off this):** the whole left-stick
range is **WALK** (tilt only scales the walk SPEED, light→brisk), and **RUN is exclusively
the hold-B / hold-Shift sprint**. So stick-only movement — even at full tilt — reads as a
walk, and the aggressive/committed "run" presentation (e.g. the sword's out-to-the-side
"ninja" carry, the deep run lean) belongs to the hold-B RUN only. In the rig this maps to
`sprintB` (the hold-B speed band), NOT the stick-speed `runB`. Gate run-only pose flourishes
on `sprintB`.

- **Mouse:** HIDDEN while over the window and drives the camera, but NEVER locked/captured
  (`hideCursor` = GLFW_CURSOR_HIDDEN). Push it past the window edge and it reappears as a
  normal OS cursor usable elsewhere. Look is gated on `isCursorOnScreen() and
  isWindowFocused()`. This is deliberate — the owner needs the mouse usable outside the
  game; do NOT reintroduce `disableCursor`/pointer-lock.
- **Move:** WASD / left stick, camera-relative; the hero turns to face travel. ZERO lag
  (see FEEL RULES): stick tilt maps straight to speed each frame — light tilt walks, full
  tilt runs; keyboard runs immediately. **Sprint:** hold Shift / hold Circle-B. **Dodge roll:** Space /
  TAP Circle-B (tap-vs-hold on the same button, like ER). **Attacks:** R1/RB or LMB =
  light slash; R2/RT or Shift+LMB = heavy overhead. Actions are committed (no mid-swing
  cancels), with an **ER-style input queue**: pressed mid-action, an attack/roll buffers
  in ONE slot (last press wins; a same-frame roll press outranks attack) and fires at the
  earliest exit — the attack's chain knot (`AL_CHAIN`/`AH_CHAIN`, so mashed R1s flow) or
  the roll's end; a queued roll leaves in the direction HELD at fire time, not pressed.
  **Camera:** mouse / right stick; scroll or D-pad zoom. **Esc** opens/backs out of the
  menu (pad **Start** toggles it); QUITTING is a menu row now, not a key. The menu opens
  at launch; while it's up, gameplay input is held and the world idles.
- **Lock-on (ER):** **R3** (pad) / **middle-mouse** (kb+m) toggles lock onto the foe nearest
  screen-centre in range; with none available R3 recenters. While locked the camera swings
  onto the foe, the hero faces it (with REAL strafe/backpedal footing — crossing sidesteps,
  reversed-walk backpedal), a **glowing white dot** marks it, and a right-stick / mouse
  **flick** cycles targets; the lock drops when the foe leaves range. ER exceptions, both
  deliberate: a hold-B SPRINT while locked faces the TRAVEL direction (no sideways sprint
  exists), and an attack's recovery tail re-squares the hero onto the target fast
  (`ATK_RETRACK`) so a locked whiff isn't left pointing into empty air.
- Reserved for later, matching ER: Cross/A = jump, L1/L2 = guard/skill.

## Hard invariants & gotchas (break these and it rots)

- **Coordinates:** ground is XZ, Y up. Hero faces +Z at yaw 0; `atan2(facing.x, facing.z)`
  is the facing angle.
- **Strafe sign:** the camera looks +Z from behind, so screen-right is world −X →
  `camera.rightXZ` MUST be `(−cos yaw, 0, sin yaw)`. Flipping it mirrors L/R walking.
- **Depth z-fighting:** `rl.gl.rlSetClipPlanes(0.2, 320)` is set once at startup — the
  default 0.01..1000 wrecks depth precision and the hero's overlapping boxes flicker / look
  inverted as the camera moves. The ground sits a hair ABOVE `y = 0` (`env.GROUND_Y = 0.01`),
  where soles / prop bases are authored, so content is planted-to-slightly-embedded and never
  reads as FLOATING — off exact 0 so coplanar faces don't z-fight, but tiny so the embed is
  imperceptible. (Owner's call: a small foot clip on the run-crouch / roll beats any float.
  The old `-0.05` dropped the ground below the feet and floated everything ~2 in.)
- **Sun + shadows are ONE source** (`gfx.SUN_DIR`) feeding both the shader's sunDir and the
  shadow camera — change the light only there.
- **Shadow pass contract:** every caster draws through `game.drawCasters` (used by BOTH the
  depth pass and the lit pass, so transforms can't drift). drawMesh/drawModel use the
  MATERIAL's shader, so the depth pass swaps caster shaders to `depthShader` and back
  (`setCasterShaders`); it runs BEFORE `beginDrawing`. Terrain receives but does NOT cast,
  and FLORA is a non-caster too (`env.drawFlora`, drawn only in the lit pass with the wind
  term on) so thin swaying blades never sparkle in / desync from the shadow map.
  The ortho box tracks the hero (`focus`), snapped to shadow texels so edges don't crawl.
- **The hero is per-bone matrices, not `drawModelEx`.** `pose()` once, `draw()` replays.
- **The scene shader gammas output (`pow 1/2.2`):** author dark colours near-black.
- **Vertex alpha is the EMISSIVE channel** (255 = fully lit; lower = self-lit).
- **Prototype models/meshes are permanent** (CPU arrays stay attached; they live the whole
  program and leak at exit — fine). Don't `unloadModel` them.
- **All UI text goes through `hud.text/textW`**, and the Exo atlas is **ASCII-only** — a `·`
  or `—` renders as a tofu `?`. Keep HUD strings ASCII.
- **Fullscreen shader passes must build their ray/UV from `gl_FragCoord`** + a resolution
  uniform when drawn via `drawRectangle` — raylib maps rectangle texcoords to the tiny
  shapes-texture rect, so `fragTexCoord` is effectively CONSTANT across the quad (the sky
  hit this). `drawTexturePro` blits (the retro pass) get real 0..1 texcoords and are fine.
- **Retro pass contract:** when any filter is active the whole frame (sky + 3D) renders
  into `Retro.rt`, then blits through the combined filter shader; vignette, HUD, and menu
  draw AFTER the blit so they never crunch. Filter values are 0..1 uniforms in a fixed
  pipeline order (see gfx.zig's retroFS comment); all-zero = pass bypassed entirely.

## Next steps (not yet built)

Stamina + the stamina economy (roll/attack/sprint costs, regen delay), roll **i-frames**
(ER medium ~0.43s front-loaded), **criticals** off a stance break (the crumple + riposte —
the stagger already exists, `combat.zig`), **hyper-armor** windows during the hero's own
attacks, guarding + **guard counter** (L1/L2), AR × motion-value × defense damage (today it's
flat per-attack constants), a **status buildup** (bleed reads naturally on a toad bite), jump
(Cross/A), distinct combo follow-up anims (ER-style input buffering + chain exits are in —
see hero.zig `Queued`), bonfires, real level geometry. See `docs/ELDEN_RING.md` for the target
mechanics/numbers behind each. Combat itself (HP, poise/stance stagger, death, foe HP bars,
damage flash) is IN — `combat.zig` is the retune point.
Current gaps to remember: the roll has **no i-frames or collision** (pure anim +
committed movement); there's **no foot IK** (feet approximate the ground; a run crouch can
float/clip a touch); one leg-cycle is reused across run and sprint (no separate run mesh);
attacks reuse one anim standing or moving (no separate running attacks).
