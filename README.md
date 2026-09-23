# zig-soulslike

Third-person soulslike prototype in native **Zig 0.14.1 + raylib**, on the sibling `../zig-rts` engine
(procedural-mesh Builder, single-sun shadow-map pipeline). Every mesh, every sound and every glyph is generated in
code — there are no art assets but the UI font (Balthazar, OFL, `assets/`).

`AGENTS.md` is the architecture, the laws and the rendering invariants inherited from zig-rts. This file is what
the thing IS.

## Build & run

| script | what |
| --- | --- |
| `build.cmd` | debug build → `zig-out\bin\zig-soulslike.exe` |
| `check.cmd` | type-check only, no codegen and no link — ~2.7 s against ~10 s |
| `run.cmd` | build + launch |
| `build-release.cmd` | ReleaseFast. **Use this to judge frame rate** — debug carries Zig's safety checks through every culling loop |
| `shot.cmd` | build + headless screenshots into `shots\` |

Zig is not on PATH; the scripts name the vendored toolchain once, in `_zig.cmd`
(`..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe`, shared with the sibling repos). raylib is static-linked
from source — there is no `raylib.dll`. `zig build test` runs the unit tests.

**Flags.** `--map worlds/x.world` loads a map other than the shipped one. `--bright` clears magenta and drops the
sky, which is how a hole in the world shows up. The shot harness is `--shot`, with `--shot-only <stage>` for one
stage of it, `--shot-props` for every prop kind alone, `--shot-art` for the 2D set on contact sheets, and
`--shot-land` for the loaded map overhead and at eye level.

**Map tools**, all headless, all dev-only: `--explode <map>` breaks every generator op into one `at:` per prop in
place; `--fix-lurkers [map]` digs every lurker pool to the dweller floor; `--fix-caves [map] [--write]` drops
every chamber the land cannot roof, keeps the largest walkable one and cuts it an entrance; `--grow <map> [half]
[--write]` puts a map in a bigger world without moving the land under it; `--bake [--force]` emits the
code-authored map and refuses to overwrite one that exists.

## What exists

**Hero rig.** 18-bone FK skeleton, bone lengths as fractions of stature (Drillis & Contini / Winter). Walk on
normative sagittal hip/knee/ankle curves (Perry / Winter); run and sprint on Novacheck. Gait phase driven by
distance travelled, not time. Roll, jump, guard, parry, three melee classes (sword / dagger / club, two strokes
each), bow, wand, torch. A faint, steady body light reaches 3 m; the carried torch lights 8.

**Combat.** HP + two-tier stagger + poise + stance, stamina with a winded latch, FP, DS1-style directional block,
L2 parry with a 0.16 s window, four PoE2 resistances plus an armour curve, and ten status meters all built the way
poison is — poison, burning, chill, stun, bleed, sleep, confusion, charm, berserk, stupefy.

**Foes.** 43 kinds in 35 groups, filed by the ground they belong to, plus the spirit wolf that fights on your
side. Shared leash, sight, parry, nav-steering and dissipation contracts in `foes/foe.zig`.

| region | what is out there |
| --- | --- |
| anywhere | leechfly, blinkbat |
| ruins | shade + mourner, the owlbear (a carving that wakes when you walk up to it) |
| village | kobold warband — berserker, priest, slinger |
| forest | the Rooted, birchwight, slumber bloom, brood mother + egg sacs + broodlings, the corrupt ent, **the corrupted druidess** |
| rock | Cyclops, delver, mastodon |
| wetland | giant toad, fen lurker (a five-metre tongue that hauls you into the pool), fishman shoal — spearman, netter, shaman, the slime (halves itself, twice, and the protrusion stupefies) |
| ash | cinder wake, salt husk |
| bone | skeleton archer / shieldman / greatsword, bone skitterer, ancient priest, necromancer, tolling hollow, rotgorger, the bone mimic, **the Bone Knight** |
| fungal | sporeling, mushroom mage, spore homunculus, fungal deer, **the fungal duo** |

Three bosses, each with its own bar and fog gate: the Bone Knight, the fungal duo (two bars), the corrupted
druidess.

**World.** 1000 m square ringed by cliffs, ten regions, 247 prop kinds. A region is built in three layers —
ground-hugger, understorey, canopy — and dead growth is what stops it looking like a garden. Sculptable
heightfield (40° slope limit, 0.55 m step). Caves are a second surface under it: carve a floor and a headroom,
cut an entrance through a hillside, and the hill overhead stays walkable; rock is opaque, so nothing on it sees or
shoots what is in the chamber below. Painted soil with coverage and eight edge shapes; painted liquid with a
derived coast you wade, in four kinds — water, tar, fungal soup (poison) and lava (burning, and it bites). All
four wade the same; the look, the status and the voice are what differ. Day/night clock (20-minute day) driving
every colour and shadow; sun 6→20 then the moon as anti-sun. Intermittent rain in two strengths with lightning,
late thunder and stray mist banks.

**Daily schedules.** Editor **Events** authors named schedules; **Units** assigns them to creatures or folk.
Each time slot has its own hours, hold/travel/patrol/roam orders, route and optional peaceful behavior.
Routes can be laid on the ground or edited numerically, and slots can cross midnight. No events or participants
are placed automatically. See [authoring schedules](docs/SCHEDULES.md).

**Progression.** Souls drop where you die and are spent only on an 81-node radial passive tree (PoE2-shaped,
three arms, six branches, six bridges). Taking a node IS the level-up — no point pool. Seven attributes, all
raised via nodes. Equipment: 42 pieces, one row each, across 12 doll sockets, every socket real. Three memorized
sorcery slots off eleven scrolls. Gold is the second currency and is kept on death — it buys the shelf, and with
smithing stone it buys weapon tiers, +0 to +10 per armament.

**Systems.** StarCraft-style trigger machine (conditions + actions, switches / counters / timers), BG2-style
dialog with live-rendered speaker portraits, three NPC kinds (wanderer, merchant, smith). A trade counter the
merchant and the smith open off a trigger — one screen, buy and sell on the shelf, stone-and-coin weapon tiers at
the anvil. All of it authored in the `.world` file, not in Zig; the grammar is in `AGENTS.md`.

**Save.** Three slots, written only by sitting at a bonfire, each with the thumbnail taken there. Text files in
the map's own `key: value` grammar.

**Menus.** Boot screen over a live 3D backdrop; pause card with a Debug screen carrying a stats overlay,
wireframe, time scale, an hour scrub and 15 layerable retro post-filters with PS1 / CRT / VHS / Game Boy presets.

## The editor

Menu > Editor. Layered StarEdit-style: ground sculpt, cave carve and entrance brushes, a **Surface / Underground**
level switch (the hill comes off every chamber; brushes, placement and picking all work the level you are on, and
the Ground brushes shape the chamber floor and raise or lower its ceiling), soil and liquid brushes, prop and unit
placement (foes and NPCs alike), zones, clearings, loot, triggers, dialog trees, undo/redo, cut/copy/paste, grid
snap, object viewer, sound jukebox, FX bench, bake-time sound filter rack. **F6** drops into a walled arena
against the one creature under the cursor and hands your map back when you leave. **F5** playtests.

Ground starts with a compact **Cliffs** palette: click or drag Raise cliff / Lower cliff at a chosen height, or
drag a Ramp from foot to top. **Sheer** drags along the top of a slope that ought to be a cliff and spends the
grade across the brush at one exact cut instead, leaving the land either side of the band alone. **Waterfall**
paints flowing water along an existing cliff edge (Shift removes it); a cave entrance can remain open behind the
curtain.

**Caves** offers Tunnel and Chamber presets, connected drag strokes, automatic floor fitting, and a graded
Entrance tool. Inside / Surface hides or shows both the ceiling and the hill above, and `I` puts the eye on the
chamber floor looking down the passage. Carving preserves a sculpted floor; Fill restores rock; undo restores a
whole gesture. The representation holds **one** underground floor/ceiling interval per horizontal
position — independently stacked tunnels are not representable.
[Research and design decisions](docs/TERRAIN_EDITOR_RESEARCH.md) compare SC2, Fortnite, Unity, Roblox, Skyrim,
Deep Rock Galactic, and volumetric alternatives.

Every brush and every rule behind them is in `AGENTS.md`.

## Performance

Roughly **17,000 static props and 8,000 colliders; a frame draws about 975 in the city and 1,250 in the wood** —
read off Debug > Stats, which `--shot` also captures. Nothing pins those figures: `env`'s "replaying the SHIPPED
map produces a stable world" test asks only that a replay match itself and stay inside `MAX_PROPS` / `MAX_SOLIDS`,
so they drift with every pass over the map.

Props are indexed into a uniform grid and culled per cell against the view frustum, per-kind view distances, and —
for the sun's depth pass — whether a caster's shadow can physically reach the shadow box. Collision and arrow
flight query the same grid. **If `drawn` approaches `props`, a culler has been defeated.**

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

Camera sits over the hero's right shoulder; movement is camera-relative and he turns to face travel. The mouse is
hidden but **never captured** — push it past the window edge and it returns as a normal cursor. Attacks and the
roll are committed, with a one-slot input buffer that fires at the earliest exit. Locked on, he strafes and
backpedals with real footing; a hold-B sprint faces travel instead.

The jump costs no stamina and is committed: no double jump, and a swing pressed mid-air buffers and fires on
landing. Heading and speed are set at takeoff; the stick only bends the arc. He clears 1.4 m — five terrain risers
where a walk climbs two — and flies over what he is above and nothing else, creatures included. No jump attack.
The fall is free under 4 m and certain death at 13.

**Ladders** are placed in the editor and run up cliffs and structures. Interact to get on; forward climbs, back
climbs down, back + sprint slides; jump or roll lets go. Nothing else can be done while you are on one, and a blow
that lands peels you off it. **You never ride the last rungs**: the moment your arms are clear of the lip the
climb hands over to a haul — press, knee up, stand — and puts you a full stride in from the edge. The watchtower
is hollow, 23 m to its roof, with four boarded storeys and a hatch in each on a different quarter of the shaft, so
every floor is crossed rather than passed through. The roof has no rail. Nothing but the player climbs, so a
ladder is an escape from whatever cannot follow.
