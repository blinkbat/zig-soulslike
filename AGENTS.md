# AGENTS.md — zig-soulslike

A third-person **soulslike** prototype in native **Zig 0.14.1 + raylib**. Founded on the
sibling `../zig-rts` rendering engine (procedural-mesh `Builder`, single-sun shadow-map
pipeline, Exo HUD), which itself descends from `../zig-diablo`.

Keep this file lean. Prefer no comments in code; write succinct ones for novel/edge cases.
Reuse existing helpers before adding new code. Don't make ad-hoc product/design decisions —
ask. The owner (David) drives the design; implement what's asked and nothing extra.

## What exists (first demo = locomotion + camera)

A convincingly **human** hero that **walks / runs / sprints / dodge-rolls**, under a
**third-person over-the-shoulder camera**, in a **lit 3D world with cast shadows**: a
golden-hour plain (warm low sun vs cool slate sky, procedural cloud deck, distance haze,
vignette) dressed as a fallen kingdom — colonnade avenue, gate arch, walls, dead trees,
graves, war banners, a statue, an emissive grace ember, and colossal hazed horizon ruins.
No combat, stamina, enemies, lock-on, or jump yet.
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
- Don't commit, push, or create branches unless explicitly asked.

## Module map

- `main.zig`   — entry; `--shot` = headless screenshot harness.
- `game.zig`   — window/loop, input (mouse + gamepad), camera-relative movement + facing,
                 dodge-roll trigger, render orchestration (sun depth pass → retro capture
                 → lit main pass → filter blit → vignette/HUD/menu crisp), sky, HUD, and
                 the `--shot` harness (which also captures filter + menu verification shots).
- `menu.zig`   — the pause/debug menu (OPEN AT LAUNCH: Continue / Debug / Quit). Debug
                 holds Stats / Wireframe / Time Scale and the Retro Filters slider list
                 (15 filters + presets), all driving gfx.Retro / loop toggles. Inspired by
                 ../crawler's pause -> Debug -> Retro Filters tree.
- `hero.zig`   — THE HERO. Anthropometric FK skeleton + every animation (idle/walk/run/
                 sprint/roll). Start here for anything about how the character moves.
- `camera.zig` — third-person over-the-shoulder orbit rig (yaw + clamped pitch, zoom,
                 shoulder offset, `recenter`), and the camera-relative ground basis.
- `gfx.zig`    — scene shader (warm hard sun + cast shadows + hemisphere ambient + rim
                 light on non-terrain + sun-banked distance haze + gamma/dither + a flora
                 wind term gated by `windAmt`/`setWind`), the sun
                 shadow-map depth pass, the mesh `Builder`, the fullscreen `Sky` shader
                 (gradient + sun aureole/disc + fbm cloud deck; ray from gl_FragCoord —
                 fragTexCoord is CONSTANT for drawRectangle), and the `Vignette` overlay.
                 Adapted from zig-rts by REMOVING fog-of-war (a soulslike is fully lit).
- `env.zig`    — procedural ground plane (extends far past the playable bounds so it
                 dissolves fully into haze) + a hand-placed prop layout: columns, gate
                 arch, walls, trees, graves, swords, banners, statue, grace ember,
                 horizon giants, and a seeded flora scatter (kind-indexed models, one
                 mesh each).
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
- **ROLL** — a committed dodge: crouch into a tight tuck, ONE forward somersault about a low
  ball centre, ease back to a stand; fast ease-out lunge in the roll direction. No float.

Blends: idle↔walk by a `moving` ease; walk↔run↔sprint by ground SPEED (`runB`/`sprintB`).

## Controls (`game.zig`)

Keyboard+mouse OR gamepad; the pad follows **Elden Ring's default layout**.

- **Mouse:** HIDDEN while over the window and drives the camera, but NEVER locked/captured
  (`hideCursor` = GLFW_CURSOR_HIDDEN). Push it past the window edge and it reappears as a
  normal OS cursor usable elsewhere. Look is gated on `isCursorOnScreen() and
  isWindowFocused()`. This is deliberate — the owner needs the mouse usable outside the
  game; do NOT reintroduce `disableCursor`/pointer-lock.
- **Move:** WASD / left stick (analog: light tilt walks, full runs), camera-relative; the
  hero turns to face travel. **Sprint:** hold Shift / hold Circle-B. **Dodge roll:** Space /
  TAP Circle-B (tap-vs-hold on the same button, like ER). **Camera:** mouse / right stick;
  scroll or D-pad zoom; **R3** recenters behind the hero. **Esc** opens/backs out of the
  menu (pad **Start** toggles it); QUITTING is a menu row now, not a key. The menu opens
  at launch; while it's up, gameplay input is held and the world idles.
- Reserved for later, matching ER: Cross/A = jump, L1/R1/L2/R2 = combat, R3 = lock-on.

## Hard invariants & gotchas (break these and it rots)

- **Coordinates:** ground is XZ, Y up. Hero faces +Z at yaw 0; `atan2(facing.x, facing.z)`
  is the facing angle.
- **Strafe sign:** the camera looks +Z from behind, so screen-right is world −X →
  `camera.rightXZ` MUST be `(−cos yaw, 0, sin yaw)`. Flipping it mirrors L/R walking.
- **Depth z-fighting:** `rl.gl.rlSetClipPlanes(0.2, 320)` is set once at startup — the
  default 0.01..1000 wrecks depth precision and the hero's overlapping boxes flicker / look
  inverted as the camera moves. The ground sits at `y = -0.05` (env `GROUND_Y`) so soles /
  prop bases aren't coplanar with it (and to give the run crouch headroom).
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

Stamina, lock-on, attacks (L1/R1/L2/R2), jump (Cross/A), bonfires, real level geometry +
collision. Current gaps to remember: the roll has **no i-frames or collision** (pure anim +
committed movement); there's **no foot IK** (feet approximate the ground; a run crouch can
float/clip a touch); one leg-cycle is reused across run and sprint (no separate run mesh).
