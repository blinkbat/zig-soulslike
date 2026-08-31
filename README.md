# zig-soulslike

Third-person soulslike prototype in native **Zig 0.14.1 + raylib**, on the sibling `../zig-rts` engine
(procedural-mesh Builder, single-sun shadow-map pipeline). UI font is Balthazar (OFL, `assets/`).

See `AGENTS.md` for architecture, laws and the rendering invariants inherited from zig-rts.

## Build & run

```
build.cmd          debug build -> zig-out\bin\zig-soulslike.exe
run.cmd            build + launch
shot.cmd           build + headless screenshots into shots\
build-release.cmd  use this for playtesting at full prop density
```

Zig is not on PATH; the scripts use the vendored toolchain at
`..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe` (shared with the sibling repos). raylib is static-linked
from source — there is no `raylib.dll`. `zig build test` runs the unit tests.

Flags: `--shot` (headless screenshot harness), `--shot-props` (every prop kind alone), `--map worlds/x.world`,
`--explode worlds/x.world` (break every generator op into one `at:` per prop, in place).

## What exists

**Hero rig.** 18-bone FK skeleton, bone lengths as fractions of stature (Drillis & Contini / Winter). Walk on
normative sagittal hip/knee/ankle curves (Perry / Winter); run and sprint on Novacheck. Gait phase driven by
distance travelled, not time. Roll, jump, guard, parry, three melee classes (sword / dagger / club, two strokes
each), bow, wand, torch.

**Combat.** HP + two-tier stagger + poise + stance, stamina with a winded latch, FP, DS1-style directional
block, L2 parry with a 0.16 s window, four PoE2 resistances plus an armour curve, ten status meters built the
way poison is — poison, burning, chill, stun, bleed, sleep, confusion, charm, berserk, stupefy.

**Foes.** 37 kinds in 29 groups: toad, skeletal archer, ogre, kobold warband (3 roles), brood mother + sacs +
broodlings, skeletal warriors (2), Bone Knight (boss, with boss bar and fog gate), shade + mourner, leechfly,
rooted, sporeling, delver, necromancer, fungal deer, mushroom mage, fen lurker, spore homunculus, bone
skitterer, ancient priest, tolling hollow, slumber bloom, cinder wake, rotgorger, birchwight, salt husk,
fishman shoal (3 roles), blinkbat, and the fungal duo (second boss, two bars), plus the spirit wolf that fights
on your side. Shared leash, sight, parry, nav-steering and dissipation contracts in `foe.zig`.

**World.** 560 m square ringed by cliffs, five regions, 161 prop kinds in three layers each. Sculptable
heightfield (40° slope limit, 0.55 m step). Painted soil with coverage and eight edge shapes; painted liquid
with a derived coast you wade, in four kinds — water, tar, fungal soup (poison) and lava (burning, and it
bites). All four wade the same; the look, the status and the voice are what differ. Day/night clock (~20 min day) driving every colour and shadow; sun 6→20 then the
moon as anti-sun. Intermittent rain in two strengths with lightning, late thunder and stray mist banks.

**Progression.** Souls drop where you die and are spent only on an 81-node radial passive tree (PoE2-shaped,
three arms, six branches, six bridges). Taking a node IS the level-up — no point pool. Seven attributes, all
raised via nodes. Equipment: 21 pieces, one row each, across 12 doll sockets, every socket real. Three
memorized sorcery slots off nine scrolls. Gold is the second currency and is kept on death — it buys the
shelf, and with smithing stone it buys weapon tiers, +0 to +10 per armament.

**Systems.** StarCraft-style trigger machine (conditions + actions, switches / counters / timers), BG2-style
dialog with live-rendered speaker portraits, three NPC kinds (wanderer, merchant, smith). A trade counter the
merchant and the smith open off a trigger — one screen, buy and sell on the shelf, stone-and-coin weapon tiers
at the anvil. All of it authored in the `.world` file, not in Zig — grammar in `AGENTS.md`.

**Editor** (Menu > Editor). Layered StarEdit-style: ground sculpt, soil and liquid brushes, prop and unit
placement (foes and NPCs alike), zones, clearings, loot, undo/redo, cut/copy/paste, grid snap, object viewer,
sound jukebox, FX bench, bake-time sound filter rack. Cannot yet author triggers or dialogs.

**Save.** Three slots, written only by sitting at a bonfire, each with the thumbnail taken there. Text files in
the map's own `key: value` grammar.

**Menus.** Boot screen over a live 3D backdrop; pause card with a Debug screen carrying a stats overlay,
wireframe, time scale, an hour scrub and 15 layerable retro post-filters with PS1 / CRT / VHS / Game Boy
presets.

## Performance

**17,272 static props and 1,819 colliders; a frame draws about 975 in the city and 1,250 in the wood** — read
off Debug > Stats in `shots/91_stats_city.png` and `92_stats_wood.png`. The first two numbers are pinned by
`env`'s "replaying the SHIPPED map produces a stable world" test. **This paragraph is the copy that goes stale
when a props rework moves them — move it together with that test, all of it or none.**

Props are indexed into a uniform grid and culled per cell against the view frustum, per-kind view distances,
and — for the sun's depth pass — whether a caster's shadow can physically reach the shadow box. Collision and
arrow flight query the same grid. If `drawn` approaches `props`, a culler has been defeated. The debug build
carries Zig's safety checks through every culling loop, so use `build-release.cmd` to judge frame rate.

## Controls

Keyboard + mouse **or** a gamepad (Elden Ring default layout).

| Action | Keyboard / Mouse | Gamepad |
| --- | --- | --- |
| Move | WASD | Left stick (tilt is the speed) |
| Camera | Mouse | Right stick |
| Sprint | Hold Shift | Hold Circle / B |
| Dodge roll | Space | Tap Circle / B |
| Jump | V | Cross / A |
| Light attack | LMB | R1 / RB |
| Heavy attack | Shift + LMB | R2 / RT |
| Guard (shield) / cast (wand) | Hold RMB | Hold L1 / LB |
| Parry (shield) | C | L2 / LT |
| Aim the bow | Hold RMB | Hold L2 / LT |
| Lock on / cycle target | Middle mouse / flick | R3 / flick |
| Sword ↔ bow | Q | D-pad right |
| Shield ↔ wand | F | D-pad left |
| Cycle memorized sorcery | G | D-pad up |
| Plain ↔ fire arrow | U | character book's ammo slot |
| Drink / cycle flask | R / T | Square / X / D-pad down |
| Rest / speak / open / mount a ladder | Y | Triangle / Y |
| Answer in a conversation | Up/Down or 1-9, Enter or Y | D-pad up/down, Cross / A |
| Zoom | Scroll wheel | — |
| Menu | Esc | Select |
| Character book | Tab | Start |
| Scrub the world clock | Menu > Debug > Hour | same, on the d-pad |
| Borderless fullscreen | Alt + Enter | — |

Camera sits over the hero's right shoulder; movement is camera-relative and he turns to face travel. The mouse
is hidden but **never captured** — push it past the window edge and it returns as a normal cursor. Attacks and
the roll are committed, with a one-slot input buffer that fires at the earliest exit. Locked on, he strafes and
backpedals with real footing; a hold-B sprint faces travel instead.

The jump costs no stamina and is committed: no double jump, and a swing pressed mid-air buffers and fires on
landing. Heading and speed are set at takeoff; the stick only bends the arc. He clears 1 m — three terrain
risers where a walk climbs two — and flies over what he is above and nothing else, creatures included. No jump
attack, no fall damage.

**Ladders** are placed in the editor and run up cliffs and structures. Interact to get on; forward climbs, back
climbs down, back + sprint slides; jump or roll lets go. Nothing else can be done while you are on one, and a
blow that lands peels you off it. The watchtower is hollow and now has two flights and a hatch in each floor,
so it can be climbed to its roof — which has no rail. Nothing but the player climbs, so a ladder is an escape
from whatever cannot follow.
