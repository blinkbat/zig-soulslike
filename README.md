# zig-soulslike

A third-person soulslike prototype in native **Zig 0.14.1 + raylib**, built on the
sibling `../zig-rts` rendering engine (procedural-mesh Builder, single-sun shadow-map
pipeline). UI is set in **Balthazar** (OFL, in `assets/`).

## First demo

- A **fully articulated human** hero — proportioned from real anthropometric data
  (body-segment lengths as fractions of stature, Drillis & Contini 1966 / Winter's
  *Biomechanics and Motor Control of Human Movement*) — that **walks** with a real gait
  cycle (normative sagittal hip/knee/ankle kinematics after Perry's *Gait Analysis* /
  Winter, contralateral arm swing, pelvic bob/sway/rotation).
- A **third-person over-the-shoulder camera** you can rotate freely (mouse look),
  souls-style, with scroll zoom.
- A **menu (open at launch)** — Continue / Debug / Quit — whose Debug screen has a
  stats overlay, wireframe, time scale, and **15 layerable retro post-filters**
  (pixelate, chroma fringe, posterize, dither, Game Boy, CGA, 16-color palette, sepia,
  mono, amber CRT, ink edges, scanlines, CRT curvature, VHS, film grain) with PS1 /
  CRT / VHS / Game Boy one-press presets.
- A **lit 3D world with cast shadows** (warm golden-hour sun + hemisphere ambient +
  shadow map + distance haze), a shader sky with a cloud deck and sun aureole, and
  **point-light fire** — torches, braziers and campfires that actually light the rooms
  they stand in, with guttering flames.

## The world

A **560 m square** ringed by cliffs, holding five regions that each read as their own place.

The ground has a **shape you sculpt**: raise, lower, smooth and flatten it with a brush in the editor,
and the hero walks it with a real slope limit (about 40°) and a step height — he takes a bank or a
terrace lip without thinking about it, slides along a face too steep to climb, and cannot get up a
cliff at all. Foes are held to the same rules, so nothing chases you up a wall. The shipped map is
deliberately flat; the elevation is there for the worlds you build next.

- **centre / south — the fallen avenue.** Where you start: colonnade, gate arch, ruined walls,
  dead trees, graves, war banners, a glowing grace ember.
- **north — the Fallen City.** A processional way to a paved plaza, broken perimeter walls, a
  quarter of ruined house shells, two **watchtowers** with dark ground rooms, abandoned carts,
  and a **wayside chapel you can walk into** — still roofed over its altar end, so the inside is
  genuinely dark and the standing torches are what let you see it. A colossal gate closes the
  view to the north.
- **east — the Tarn.** A shallow peat lake you **wade straight through**, with drowned columns
  standing in it, a stone causeway running out and stopping where its middle span fell in,
  willows over the margin and reed beds in the shallows.
- **west — the Old Wood.** Great trees in three variants with layered canopies, ferns, brambles
  and bushes underfoot, mossy boulders, a **standing-stone circle** in a clearing, and a
  woodcutter's **cottage** whose campfire is still ringed in stone.
- **south — the Windswept Downs.** Open, dry and nearly empty — the region that makes the others
  feel dense. Lone trees, field stones, old graves, a watchtower on the rise.

Every region is dressed in three layers — ground cover, understorey, canopy — from a registry of
**80 prop kinds**: great trees in three variants, conifers, birches, dead snags and saplings;
ferns, brambles, thickets, nettles, thistles, foxgloves, heather, gorse, clover, moss, mushrooms
and bracken; boulders, outcrops, scree and cairns; wells, shrines, post lanterns, fences, barrels,
woodpiles, sarcophagi, stair fragments, gibbets and bones; torches, braziers and campfires that
light what's around them.

**17,253 static props and 1,859 colliders, of which a frame draws about 975 in the city and 1,250 in
the wood** (read straight off Debug > Stats in `shots/91_stats_city.png` and `92_stats_wood.png`; the
first two numbers are pinned by `env`'s "replaying the SHIPPED map produces a stable world" test —
this paragraph is the copy that went stale when the props rework moved them, so move it together
with that test and AGENTS.md's own line, all three or none): props are
indexed into a uniform grid and culled per cell
against the view frustum, per-kind view distances, and — for the sun's depth pass — whether a
caster's shadow can physically reach the shadow box. Collision and arrow flight query the same grid.
Turn on **Debug > Stats** to watch those numbers live. For playtesting at this density use
`build-release.cmd`; the debug build carries Zig's safety checks through every culling loop.

## Controls

Keyboard + mouse **or** a gamepad (Elden Ring default layout):

| Action | Keyboard / Mouse | Gamepad (Elden Ring binds) |
| --- | --- | --- |
| Move | WASD | Left stick (analog — tilt is the speed, every frame) |
| Camera | Mouse | Right stick |
| Sprint | Hold Shift | **Hold** Circle / B (dash) |
| Dodge roll | Space | **Tap** Circle / B |
| Light slash | LMB | R1 / RB |
| Heavy overhead | Shift + LMB | R2 / RT |
| Lock on / cycle target | Middle mouse / flick | R3 (right-stick click) / flick |
| Zoom | Scroll wheel | D-pad up / down |
| Menu (Continue / Debug / Quit) | Esc | Start |
| Borderless fullscreen | Alt + Enter | — |

The camera sits over the hero's **right shoulder**; movement is camera-relative and the hero turns
to face the direction of travel. The mouse is **hidden but never captured** — push it past the
window edge and it comes back as a normal cursor, so the pointer can always escape. Attacks and the
roll are committed, with an Elden-Ring-style one-slot input buffer that fires at the earliest exit.
While locked on, the hero faces the target with real strafe/backpedal footing and R3 cycles targets.
Reserved for later, matching Elden Ring: Cross/A = jump, L1/L2 = guard / skill.

## Build & run

```
build.cmd        REM debug build -> zig-out\bin\zig-soulslike.exe
run.cmd          REM build + launch
shot.cmd         REM build + headless screenshots into shots\ (gaits, foes, world tour, maps, terrain)
build-release.cmd
```

Zig is not on PATH; the scripts use the vendored toolchain at
`..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe` (shared with the sibling repos).
raylib is static-linked from source — there is no `raylib.dll`.

See `AGENTS.md` for architecture and the rendering invariants inherited from zig-rts.
