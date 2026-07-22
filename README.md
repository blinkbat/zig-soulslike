# zig-soulslike

A third-person soulslike prototype in native **Zig 0.14.1 + raylib**, built on the
sibling `../zig-rts` rendering engine (procedural-mesh Builder, single-sun shadow-map
pipeline, Exo HUD).

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
  shadow map + distance haze), a shader sky with a cloud deck and sun aureole, and a
  ruined-kingdom set: colonnade avenue, gate arch, walls, dead trees, graves, war
  banners, a glowing grace ember, colossal ruin silhouettes on the horizon, and a
  seeded meadow scatter (grass tufts, patches, reeds, shrubs, flowers).

## Controls

Keyboard + mouse **or** a gamepad (Elden Ring default layout):

| Action | Keyboard / Mouse | Gamepad (Elden Ring binds) |
| --- | --- | --- |
| Move | WASD | Left stick (analog — light tilt walks, full tilt runs) |
| Camera | Mouse | Right stick |
| Sprint | Hold Shift | **Hold** Circle / B (dash) |
| Dodge roll | Space | **Tap** Circle / B |
| Zoom | Scroll wheel | D-pad up / down |
| Recenter camera | — | R3 (right-stick click) |
| Free / recapture mouse | Tab | — (pad never locks the pointer) |
| Menu (Continue / Debug / Quit) | Esc | Start |

The camera sits over the hero's **right shoulder**; movement is camera-relative and the
hero turns to face the direction of travel. Free-look captures the mouse — **Tab** frees it
(or lose window focus) so the pointer can always escape to exit. The dodge roll is a
committed tuck-and-somersault in the input direction (or forward). Reserved for later,
matching Elden Ring: Cross/A = jump, L1/R1/L2/R2 = combat, R3 = lock-on.

## Build & run

```
build.cmd        REM debug build -> zig-out\bin\zig-soulslike.exe
run.cmd          REM build + launch
shot.cmd         REM build + headless walk-cycle screenshots into shots\
build-release.cmd
```

Zig is not on PATH; the scripts use the vendored toolchain at
`..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe` (shared with the sibling repos).
raylib is static-linked from source — there is no `raylib.dll`.

See `AGENTS.md` for architecture and the rendering invariants inherited from zig-rts.
