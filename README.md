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
- A **boot screen** — New Game / Load Game / Options / Editor / Quit — over a live 3D
  backdrop the camera walks slowly round. **Three save slots**, each shown by the picture
  taken at the bonfire it was written at. You save by **sitting down at a bonfire** and
  nowhere else; a fire writes over whatever slot you are playing.
- A **pause menu** — Continue / Options / Editor / Debug / Back to Title — whose Debug screen has a
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
  dead trees, graves, war banners, a bonfire camp with a smoke plume you can see from across the plain.
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

### …and a day that runs through it

The world has a **clock**, and the light is the whole of what it does. A real day takes about twenty
minutes: the sun climbs out of the east at six, arcs over, and goes down in the west at eight, and once
it is under the horizon the **moon** takes over from the opposite quarter — so there is always something
casting and you are never in the dark you cannot fight in.

Everything moves with it. **Shadows swing round and stretch** as the sun drops. The sky is banked red at
both ends of the day, opens cool and clear by mid-morning, and goes to deep navy with a **field of stars**
over it at night. The haze in the distance takes the colour of the hour; steel and marble stop glinting
when there is nothing left to glint at; the campfires stop being decoration and become the only warm
thing in the frame.

A **bonfire will hold you until morning or until evening** — the two halves of the clock worth choosing
between: half past eight, in the clearest light of the day, or nine at night, with the sun an hour gone and
the moon already casting. A fire never takes you backwards, so asking for the hour you are sitting in costs
a whole day. The
debug menu carries an **Hour** row you can scrub and hold, and in the editor `,` and `.` sweep the day so a
belt of trees can be judged under every light it will ever stand in rather than under one permanent
afternoon.

### …and something to carry into it

A **pitch torch** goes in either hand from the character book's four weapon cells. It is the only light you
own: an eight-metre pool of guttering firelight that walks with you, so the chapel's roofed altar end, the
watchtower ground rooms and the whole of the small hours stop being places you squint at. It costs no stamina
and no focus and it does nothing on either button — what it costs is the hand. Put it in the left and the
shield is on the ground: light or a block, never both. Put it in the right and you keep the shield and give up
the sword instead, which is the same trade read from the other end.

## Someone to talk to

At the bonfire where you start there is now a **wanderer** — a hooded traveller with a walking staff who
looks up when you come near, raises a hand, and has something to say about the road north. He is the first
body in this world that is not trying to kill you: no health bar, no aggro, a name, and a conversation you
read off a framed panel with the world dimmed behind it. Answer with the number keys or the stick; some
answers only appear once you have heard the thing that unlocks them.

Behind him is a **trigger system lifted from StarCraft's map editor**: a trigger is a list of CONDITIONS and a
list of ACTIONS, every condition must hold, and then the actions run in order. The conditions can ask whether
a named switch is set, whether a counter has reached a number, whether a timer has run out, how long you have
been in this world, whether you are standing in a rectangle, whether you are near a particular person,
whether you have heard a particular conversation through to its end, and how many of a given foe are dead or
still standing. The actions can open a conversation, put a line of narration on screen, set or flip a switch,
move a counter, start a timer, wait, or keep themselves alive for next time. All of it — the triggers, the
conversations and the people — is **written in the `.world` file** alongside the props, so the map still owns
everything about the map. `AGENTS.md` has the grammar.

Every region is dressed in three layers — ground cover, understorey, canopy — from a registry of
**136 prop kinds**: great trees in three variants, conifers, birches, dead snags and saplings;
ferns, brambles, thickets, nettles, thistles, foxgloves, heather, gorse, clover, moss, mushrooms
and bracken; boulders, outcrops, scree and cairns; wells, shrines, post lanterns, fences, barrels,
woodpiles, sarcophagi, stair fragments, gibbets and bones; torches, braziers and campfires that
light what's around them.

**17,272 static props and 1,819 colliders, of which a frame draws about 975 in the city and 1,250 in
the wood** (read straight off Debug > Stats in `shots/91_stats_city.png` and `92_stats_wood.png`; the
first two numbers are pinned by `env`'s "replaying the SHIPPED map produces a stable world" test —
this paragraph is the copy that goes stale when a props rework moves them, so move it together
with that test, all of it or none): props are
indexed into a uniform grid and culled per cell
against the view frustum, per-kind view distances, and — for the sun's depth pass — whether a
caster's shadow can physically reach the shadow box. Collision and arrow flight query the same grid.
Turn on **Debug > Stats** to watch those numbers live. For playtesting at this density use
`build-release.cmd`; the debug build carries Zig's safety checks through every culling loop.

## Something to spend the souls on

The souls you drop and walk back for are spent on a **radial passive tree** in the shape of Path of Exile 2's
— and they are the only thing spent on it, and it is the only thing they are spent on. You stand at the hub
and three arms run out of it: one for heavy arms, flesh and what a guard turns aside; one for the roll, luck,
a light edge and the blood that answers a poison; one for FP, what a cast costs and what it deals. They are
not named anywhere — colour and direction are what tell you which is which — and none of them is a class:
all three hang off the middle, so all three are open from the first souls you spend.

**Taking a node IS the level up.** There is no pool of points to hold: one press pays the souls and puts the
node on the board. What stops you is the path — a node opens as soon as anything it connects to is yours, so
you climb a branch a node at a time toward whichever capstone you want, and either side of an arm gets you to
its tip. Prices are measured against what a body is worth: your first node costs about three skeletal
archers, and the whole one-and-twenty is a game's worth of killing.

There is no attribute screen any more: every attribute past the starting sheet comes off a node here. The
wheel is the character book's last page and you can read it anywhere, but you spend **only at a bonfire**.
Sitting at one is its own screen: you sit off to the right of the frame with the fire, and the bonfire's menu
is a list down the left — **Level Up**, which opens the wheel, **Memorize Spells**, which opens the rack, the
two waits, and **Leave Bonfire**, which is the only way back out. Walk the tree with the left stick and zoom
it with the right.

## The rod carries three

Every sorcery is written on a **scroll**, and owning the scroll is not the same as having the spell about you.
The rod casts only what is **memorized**: three slots, filled sitting at a bonfire and read in the fight,
which is Elden Ring's memory slots and the reason a wand build is a decision rather than a menu. D-pad up
cycles what is in the rack, in the order you put it there; the character book's **Spells** page is where you
read what each one costs, what it does, and which scrolls you are still missing — read-only, because a rack
you can fill mid-fight is a rack with no slots in it.

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
| Guard (shield) / cast (wand) | Hold RMB | Hold L1 / LB |
| Parry (shield) | C | L2 / LT |
| Aim the bow | Hold RMB | Hold L2 / LT |
| Sword ↔ bow | Q | D-pad right |
| Shield ↔ wand | F | D-pad left |
| Cycle memorized sorcery | G | D-pad up |
| Plain ↔ fire arrow | U | — (character book's ammo slot) |
| Drink / cycle flask | R / T | Square / X / D-pad down |
| Jump | V | Cross / A |
| Rest / speak / open | Y | Triangle / Y |
| Answer in a conversation | Up / Down or 1-9, Enter or Y | D-pad up / down, Cross / A |
| Zoom | Scroll wheel | — |
| Menu (Continue / Debug / Quit) | Esc | Select |
| Scrub the world clock | Menu > Debug > Hour (Left/Right, Shift coarse, hold to sweep, Enter holds it) | same, on the d-pad |
| Character book | Tab | Start |
| Borderless fullscreen | Alt + Enter | — |

The camera sits over the hero's **right shoulder**; movement is camera-relative and the hero turns
to face the direction of travel. The mouse is **hidden but never captured** — push it past the
window edge and it comes back as a normal cursor, so the pointer can always escape. Attacks and the
roll are committed, with an Elden-Ring-style one-slot input buffer that fires at the earliest exit.
While locked on, the hero faces the target with real strafe/backpedal footing and R3 cycles targets.
**Cross/A jumps**, matching Elden Ring. It is free — no stamina — and it is committed: no double jump, and a
swing pressed in mid-air buffers and goes off the frame he lands. The heading and speed are set at takeoff (a
standing jump goes straight up, a sprint jump carries the sprint) and the stick may only bend the arc from
there. He clears a metre, which is three of the terrain's own risers where a walk climbs two — so a ledge is
something you answer with a button — and he flies over what he is above and nothing else, creatures included.
There is no jump attack and no fall damage.

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
