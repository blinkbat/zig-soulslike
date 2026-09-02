# The Bone Knight — where this stands and what to do next

Handover for the next session. Everything below is verified by TESTS (`zig build test`, 1044 passing), not by
eye; David plays each build and his eye is the other half. Read `AGENTS.md` first — the knight section carries
every law and every number; this file is only the plan.

## What was done (2026-08-25, one long session)

Owner's asks, in order, and what answered them:

| ask | answer | pinned by |
| --- | --- | --- |
| "less jumpbacks — last resort under heavy damage" | `RETREAT_AT` tier gates every leap door; rear blow answered by the FALL | `THE LEAP`, `A FLANK BLOW HE SHRUGS OFF`, `SWIPE-AND-LEAP` |
| "sword goes over my head / swinging at emotions" | every stroke re-authored to cross his FRONT, low; `reachIn`/`bandR`/`stepLands`; reach measured down the facing while live through the real update | `THE SWORD IS SWUNG AT THE MAN WHERE HE STANDS`, `EACH STROKE'S DECLARED REACH…` |
| "tighter particles" | rim-weighted gas, metres not scale, ember colour | gas tests |
| "he should step-turn, not turn constantly" | idle no longer tracks; `STEPTURN.least` 30 | `HE IS NOT DULL` soak (23 blows / 95% / 0.73 s) |
| "shield in the way of the sword" | door strapped to the forearm (`shieldXf`/`calibrateShield`), thrust opens the guard, sword parks right while the door comes home | `THE SWORD DOES NOT PASS THROUGH THE DOOR` (0.38–0.42 m clearance) |
| "shield floats / bizarre angles" | same strap; face-normal pins on guard / ram / slam | `THE DOOR FACES WHAT IT MEETS` |
| "more damage, more windup" | +12% / +15% | `LIGHT AND HEAVY ARE TELLABLE APART` |
| "better tells, better posture, swordsmen data" | `.hold` at the end of every gather; Pflug carry | `THE SWORD IS PRESENTED — Pflug` |
| "good parry potential" | two parries break his stance (`PARRY_STANCE`) | `HE DOES NOT FLINCH AT A POKE` |
| "orange gas" | ember palette at the one call site | — (colour is not tested) |
| global: "stun buildup = % HP over a period from HITS; nothing builds while stunned; diminishing returns on stuns and statuses" | `combat.zig`: `FOE_POISE_PER_DMG`, stunned gate, `lightWear`/`heavyWear`/`ailWear` | three new tests in `combat.zig`; warrior hyper armour and knight door restore the pool |

## The tools that made it possible — use them, don't rebuild them

- **The band test** (`THE SWORD IS SWUNG AT THE MAN WHERE HE STANDS`): throws a stroke through the REAL
  `update()` at a hero stood at four stands from `reachIn` to 0.97·`bandR`, shoves him out to
  `closestApproach` as the game would, and demands a hit at each. On a miss it prints the nearest approach and
  the man's relative distance at that frame. **This is the judge. A strip or a shot is not.**
- **The reach test**: measures each kit's arrival DOWN HIS FACING while LIVE through the real update (a keyed
  replay has no spring lag and lies), and pins `reachOut` within [−0.05, +0.65] of it.
- **`bladeDoorGap` / `doorNormal`**: blade-to-door clearance across a whole stroke; where the plank faces.
- When you need to SEE a stroke's geometry, add a temporary test that prints `wpnHere()` per frame **relative
  to `k.pos`** (I lost an hour to world coordinates that included the lunge) with `fw`/`lt` in his frame.

## Known tolerance-tight spots (a retune here will bite)

- Sweep far stand: 0.97·`bandR` sits ~10 cm inside the measured far edge. `stepLands` 0.87 is what holds it.
- Bash reach: declared 2.65 vs measured 2.46 — inside the +0.65 tolerance but the wide side of it. The door
  pose (`BASH_HIT_*`) moved three times; re-measure before touching.
- Door clearance: swat 0.38 and sweep2 0.39 against a 0.36 clearance. `CARRY_ABD` and `SWT_ABD` are
  what buy it; the Pflug hilt lives 0.48 m off the plank's right edge.
- `SWING_BEARING` 19 / `BASH.bearing` 20 are derived from the ram's subtended half-angle at 2.7 m.

## What is NOT verified and needs David's eye

1. **The Pflug carry** — the point sits at (−3.3, 1.9, 3.5) in his frame: forward, head-high, angled in ~30°.
   Whether it reads as a threat or as "holding the sword out sideways" is his call. Knob: `CARRY_SWEEP` (only
   moves the point ~0.4 m per 30°, the elbow bend converts it to roll) and `CARRY_ABD` (out/in, trades against
   the door-edge clearance).
2. **The door on the forearm** — the strap is rigid, so the door now MOVES with every arm pose: the swipe
   carries it out left and back edge-on, the bash keeps it square (elbow folded, body drives), the slam pitches
   it face-down (normal y −0.95). The winds' door poses (`BASH_WIND_*` twist −30) are un-eyeballed.
3. **The second sweep as a second forehand** — the 0.58 s re-cock draws the blade low across his front. It is
   un-live and it is a tell, but it does cross the man's line; if it reads as a swing that didn't hit, shorten
   `SWEEP2.windDur` or raise the re-cock.
4. **Gas** — rim-heavy, 1.3 m tall, ember. Not shot.
5. **The combat rule's knock-on** on every other creature: a creature's flinch is now HEALTH TAKEN × 0.82 into
   its `poiseMax`. The hero's BASE blows land on the old scale, but a levelled hero (damage scales with
   `stats.scaleFor`) now flinches everything sooner than before, where poise used to be flat per swing. If the
   mid-game feels like everything staggers, the dial is `FOE_POISE_PER_DMG` (or make it read the hero's
   `perk.dmg` out — poise poured off UNSCALED damage would restore "a light swing is a light swing").

## Next iterations, in the order I would take them

1. **Play it.** Every number above landed by math; the fight is what he asked for only if it FEELS it.
2. ~~**Strips**~~ **DONE 2026-08-25 (second pass).** `shots.KNIGHT_STRIP` is hoisted and its boom is now SOLVED
   against the swept box of everything the stroke moves — sword, door, body — with a test in `shots.zig` that
   re-measures and re-solves (`STRIP_FILL`). At 13–15 m the four strokes filled 40% of a frame aimed a metre
   over the action; they now fill 75%. `camera.FOVY` and `game.SCREEN_W`/`SCREEN_H` went public for it.
   **STILL OPEN — his call:** the fire tell (`emitGather`) scales only with `Weight`. Whether a per-stroke tell
   is wanted (a tell that says WHICH stroke, not just how heavy) is a design decision, not a fix.
3. ~~**The AI as the template**~~ **DONE for the ogre, 2026-08-25 (second pass).** The band question was asked
   and it failed: `THE CLUB LANDS ON THE MAN WHERE HE STANDS` throws slam / swipe / return / drive through the
   real update at four stands × four bearings each, and the SLAM missed three of four stands at 170° off.
   Fixed with the knight's law — `ogre.slamBearing`, a hard gate at the choose, solved off `WIND_TURN_SHARE ×
   TURN_RATE × WINDUP_DUR` plus what the crush strip subtends at that stand. `classify` now takes `scale` in
   place of `swipeInner` so both derivations read one number. 60 stands thrown and landed, 4 refused.
   `range bands…` also pins each choose band inside the bill that answers it (slam 2.30/2.96 m, swipe
   2.16–4.40/2.16–5.04, drive 7.00/7.32).
   **NOT lifted, and deliberately:** `Sense` two-tier pressure has nothing to buy on the ogre — it owns no
   retreat and no reposition, so `REPOSITION_AT`/`RETREAT_AT` would be new moves, which is design. And the
   ogre's choose bands stay PICKED (`SLAM_R` under a 2.96 m bill): deriving them off the reach the way
   `knight.bandR` does would hand him more slams, which is a change to the fight and his to make.
3b. **THE SWORD STILL CROSSES THE DOOR IN THE STATES NOBODY CHOREOGRAPHED.** The pinned clearance test covers
   the five strokes wind-to-recover and reads 0.38-0.43 m against a 0.36 m clearance. Walked across EVERY state,
   the blade centre-line comes within 0.06 m (the fall), 0.08 (a stagger), 0.13 (a chained sweep2), 0.14 (a
   chained bash), 0.15 (the awaken) — and the blade is 0.10 m in the half-width, so those are inside the plank.
   The carry rule improved the slam (0.03 to 0.18) and the shove (0.18 to 0.41) and left the rest where they
   were. Fixing it is a choreography pass over the un-authored states, or moving the door off his centre line
   (the guard pull is `-SHOULDER_HALF * H * 0.80` in `calibrateShield`) and paying for it in front coverage.
   The second is one constant and a re-solve; it moves the guard he has already signed off on.
4. **`counterFlank`'s rear answer is the FALL** on cooldown 0 — first rear poke of every fight gets the fall.
   If that reads as a script, gate it on `pressed` (the reposition tier) as well. **His eye decides.**
5. **Damage/windup** are one knob each per row; he asked for "a bit" and got 12/15%. Expect a second pass.
6. **Parry**: two parries now open him. The parry window is `foe.PARRY_LEAD`, global. A knight-specific
   longer window would be the next "badass" lever if two parries still feel unreachable.

## Laws touched this session (so you don't undo them)

- The thrust OPENS the guard now (it did not). `swipesNow` lists the sword strokes.
- `PARRY_HIT` stays 46 globally — the knight's 70 is `PARRY_STANCE`, local.
- Nothing stacks on a stunned body — stance included. The old "immunity is poise only" test was inverted on
  the owner's word.
- `Hit.poise` is IGNORED on the foe side. Any creature test that flinches a foe with `.poise` alone must use
  `.dmg` (or empty the pool first). Hyper armour / a block must hand `vit.poise` (and `stance`) back after
  `foe.reached`.

Nothing here is committed. The tree is his.
