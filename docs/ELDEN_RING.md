# Elden Ring — combat systems & numbers (reference)

A reference for Elden Ring's (ER) combat mechanics and the real numbers behind them — poise,
stagger, stance-break, damage, defense, stamina, guarding, rolling/i-frames, status buildup,
and attack pacing.

Compiled from heavy multi-source research (Fextralife wiki, Elden Ring Reforged wiki [a MOD
wiki — flagged where used], wiki.gg / Eldenpedia, datamined motion-value & poise spreadsheets,
and community breakpoint threads), cross-verified. Tags: **[DM]** datamined/wiki hard number,
**[APX]** approximate/community-tested, **[disp]** disputed across sources.

> **Frame-data convention (read first).** FromSoft animation data is authored in **30 fps
> units** (TAE ticks) but the game runs at 60 fps. Every "frames" figure on the wikis is a
> 30 fps value — **×2 for on-screen 60 fps frames, ÷30 for seconds.** A "13-frame" medium
> roll is **~0.43 s**, not 0.21 s. Getting this conversion wrong is the #1 mistake reading these numbers.

---

## 1. Poise, stagger & stance-break

ER runs **two separately-tracked meters**.

### Poise — flinch resistance ("poise HP")
- The visible poise stat is the **max of an invisible poise-HP pool**. Each hit subtracts a
  **poise-damage** value; when the pool empties **and** the attack's Damage Level exceeds the
  remaining threshold, you flinch/stagger. **[DM]**
- Internal `Toughness = displayed poise ÷ 10` is the value an attack's poise damage must
  exceed. **[DM, disp on exact scaling]**
- **No spill on break.** 1 poise left + a 50 poise-damage hit ⇒ stagger, poise resets to full;
  the excess does NOT carry to HP. **[DM]**
- **Player poise regenerates** back to full after a no-hit window; on stagger it **resets to
  max instantly**. Fextralife cites ~30 s full reset out of combat **[disp]**.
- **Enemy poise regen delay scales with max poise:** ~**6 s at ~80 poise → ~15 s at ~200**,
  then refills fast. **[DM]** ← this delay is why sustained pressure matters.
- Poise mostly matters **during your own attack animations** (hyper armor); while idle/walking/
  rolling you can be interrupted more freely. **[consensus]**

**Player poise breakpoints:** **51** = shrug most normal attacks (Knight Set = exactly 51);
**61** = trade through medium-weapon strings [APX]; **101** = trade greatsword/colossal lights,
near-uninterruptible (heaviest armor + Bull-Goat's Talisman). 51 & 101 datamined; 61 is a
build-guide figure. **[DM/APX]**

### Stance — the "poise break" that opens criticals
- A **second hidden meter**; when accumulated **stance damage** empties it the enemy
  **stance-breaks** (crumples) — wide open to a **critical**. **[DM]**
- Accrues from each hit's stance damage (independent of HP damage). Regenerates after a delay
  like enemy poise (~6–15 s) — **relent and it resets.** **[DM]**
- Rule of thumb to break: charged heavies / jump heavies / guard counters ≈ **2–4 hits** on
  standard enemies; many light R1s; bosses have big pools + fast regen so **burst windows**
  beat steady DPS. **[APX]**

### Hyper armor & Damage Levels
- **Hyper armor**: bonus poise during certain attacks (mostly **two-handed** greatswords/
  greataxes/hammers/great spears; Mace 1H is an exception) — lets you **trade through** light
  hits. Bypassed by very-high poise-damage attacks, **status procs**, and grabs. **[DM]**
- **Damage Levels** (hitstun tiers 0–11) decide the *type* of flinch: Lvl 1 short (straight-
  sword R1), Lvl 2 medium (greatsword R1), Lvl 3 long (colossal R1), Lvl 4/7/10/11 knockdown.
  Hitstun applies **only if poise damage > remaining Toughness.** **[DM]**

### Critical hits
- Stance-break/parry/backstab → crumple → **R1 executes a critical**. Damage ≈ **2.5×–4×**;
  riposte > backstab by ~25–30%. Dagger riposte **420%** AP, straight sword **345%**, colossal
  **263%**. Weapon Critical stat (÷100) multiplies it: Misericorde 140, daggers/rapiers 130. **[DM]**

### Poise/stance damage dealt by attacks
Straight sword, one-handed, "stance damage" scale **[DM]**:

| Attack | Stance dmg | ×light |
|---|---|---|
| Light R1 | 5 | 1.0 |
| Jumping light | 8 | 1.6 |
| Heavy R2 | 10 | 2.0 |
| Jumping heavy | 20 | 4.0 |
| Charged R2 | 30 | 6.0 |

Charged R2 by class: Daggers 18 · Straight 30 · Greatswords 33 · Colossal 36 · Colossal
hammers 42. **[DM]** Two-handing: **+30 % light / +10 % heavy & guard counter.** Jump ≈ ×2 the
grounded move. Unaware +20 %. **[DM]** Guard counters deal stance ≈ a fully-charged heavy.

Sources: [Poise](https://eldenring.wiki.fextralife.com/Poise) · [Stance](https://eldenring.wiki.fextralife.com/Stance) · [Hyper Armor (wiki.gg)](https://eldenring.wiki.gg/wiki/Hyper_Armor) · [How stance break works (GameRant)](https://gamerant.com/elden-ring-how-stance-break-works/) · [Critical Damage](https://eldenring.wiki.fextralife.com/Critical+Damage)

---

## 2. Damage & defense

- **Attack Rating (AR)** is computed **per damage type** then summed: `AR = Base + Base ×
  ScalingCoeff × StatSaturation`. All three (base, scaling grade, stat) must be high to matter.
  Scaling letters are buckets for the hidden coefficient: S ≥175 %, A 140–174, B 90–139,
  C 60–89, D 25–59, E 1–24. **[DM/APX]**
- **Soft caps** (AR-per-level falls off after): STR/DEX ~**20 → 55 → 80**; INT/FAI **60 → 80**;
  ARC **45 → 60**. Endurance (stamina) **15/30/50**; Mind (FP) ~35/50/60; Vigor (HP) 40/60. **[APX]**
- **Damage types:** phys (standard/strike/slash/pierce) + magic/fire/lightning/holy, resisted
  **separately**. Strike vs armor/pots, pierce enables counter-hits, fire clears frost,
  lightning amplified vs wet. **[DM]**
- **The damage formula** — flat Defense uses an **attack-ratio curve**, NOT linear subtraction:
  ```
  ratio = (AttackPower × MotionValue) / Defense
  mult  = floor 0.10  (ratio<0.125) … ~0.70 at ratio 1.0 … ceiling 0.90 (ratio≥8)
  final = AttackPower × MV × mult × ∏(1 − Negation_i)   [per type, then summed]
  ```
  Two floors to remember: **a hit always deals ≥10 %** of its pre-defense value (you can't be
  fully walled), and Defense never removes **more than 10 %** once you vastly outscale it.
  Damage negation % stacks **multiplicatively**, never additively. **[DM formula]**
- **Motion Values (MV)** = per-animation AR multiplier — **the single biggest tuning knob.**
  Light R1 ~100, heavy R2 ~120–130, **charged R2 ~150–185**, jump ~107–135, running ~105–160,
  rolling ~90. Slower/higher-commitment = higher MV (risk/reward lives here). **[DM]**
- **Two-handing:** ×1.5 effective STR (AR only), and usable at ⅔ the STR requirement. **[APX]**

Sources: [Calculating Damage](https://eldenring.wiki.fextralife.com/Calculating+Damage) · [Motion Values](https://eldenring.wiki.fextralife.com/Motion+Values) · [Damage Types](https://eldenring.wiki.fextralife.com/Damage+Types)

---

## 3. Stamina & guarding

- **Pool** is shallow: Endurance 1 → **80**, 15 → 105, 30 → 130, 50 → 155, 99 → 170. Softcaps
  15/30/50. **[DM]**
- **Regen ≈ 45 stamina/sec [APX]**, after a short **delay** post-spend; **paused** while
  attacking, blocking, sprinting. Heavy equip load **−20 % regen**. **[DM/APX]**
- **Costs:** roll/backstep = **12, flat** (load-independent) — the anchor everything else is
  tuned against (a ~155 pool ≈ ~12 rolls). Attacks are **weapon-dependent** (dagger ~7–9 →
  colossal ~30–40); heavy ≈ 1.3–1.8× the weapon's light; sprint ~8–10/s **in combat only**. **[DM/APX]**
- **Guarding:** guarded **negation %** per type (medium/greatshields = 100 % physical → no HP,
  only chip); **Guard Boost/stability** governs **stamina lost per blocked hit**. Empty your
  stamina while guarding → **guard break** (staggered, wide open — the danger is the follow-up,
  not that hit). **[DM]**
- **Guard counter** (block → immediate R2): modest bonus damage, **high stance damage** (≈ a
  charged heavy; +10 % two-handed) — the core "block → punish → stagger" loop. **[DM]**
- **Out of stamina** = can't roll/attack/sprint/block-hold → the primary death window. No HP
  penalty, pure lockout. **[DM]**

Sources: [Stamina](https://eldenring.wiki.fextralife.com/Stamina) · [Guarding](https://eldenring.wiki.fextralife.com/Guarding) · [Guard Counter (Fandom)](https://eldenring.fandom.com/wiki/Guard_Counter)

---

## 4. Dodge roll, i-frames & equip load

**Equip Load bands** (of max load, which scales with Endurance) **[DM]**:

| Band | % of max | Roll | i-frames @30/@60 (~s) | Recovery @30/@60 | Distance | Stamina |
|---|---|---|---|---|---|---|
| Light | < 30 % | fast | 13 / 26 (~0.43 s) | 8 / 16 | **4.09 m** | 12 |
| Medium | 30–69.9 % | medium | 13 / 26 (~0.43 s) | 8 / 16 | **3.21 m** | 12 |
| Heavy | 70–99.9 % | fat | 12 / 24 (~0.40 s) | **16 / 32** | **2.66 m** | 12 |
| Overloaded | ≥ 100 % | — (stumble) | 0 | long | 0.51 m | — |

- **I-frames are class-fixed** (no Adaptability/Agility stat like DS2), **front-loaded**
  (~1–2 f startup), then vulnerable travel + recovery. Light vs medium differ **only in
  distance**; heavy's **doubled recovery** is the big roll-catch liability. **[DM]**
- **Backstep: ~0 i-frames** in vanilla (the Fine Crucible Feather talisman exists to *add*
  them) — a spacing tool, cancelable into a lunge attack. **[DM]**
- Special: **Quickstep** (3 FP, 15/13 i-frames, 0 startup), **Bloodhound's Step** (5 FP,
  16/14, ~2 rolls' distance, brief invis). Instant startup is why they feel better than rolls. **[DM]**
- **Roll-catching:** enemies time delayed attacks to land in your **recovery** (after i-frames
  expire). Read: roll **on the strike**, not the wind-up; roll *toward* the attack.

Sources: [Dodging](https://eldenring.wiki.fextralife.com/Dodging) · [Equip Load](https://eldenring.wiki.fextralife.com/Equip+Load) · [Bloodhound's Step](https://eldenring.wiki.fextralife.com/Bloodhound's+Step)

---

## 5. Status effects (buildup model)

**Fill → proc → run out**, with **decay**: each hit adds a flat buildup; at threshold it **procs**.
Buildup **decays** once you stop: **base 1/s + the enemy's own 1–10/s** (big bosses shed ~11/s).
Resistances (Robustness/Immunity/Focus/Vitality) **raise the threshold, not reduce the proc.** This
is the purest "keep pressure on" system — spaced hits against a high-decay foe may **never** proc.
**[DM/V]**

**A DURATION STATUS CANNOT BE RE-APPLIED WHILE IT RUNS.** Poison, Scarlet Rot and Frostbite hold the
meter for the length of the effect — it is a state you are already in, and further buildup does
nothing until it has worn off. Only the **BURST** statuses (Hemorrhage, Madness) have nothing to
run: those resolve on the frame they proc and the meter is free to fill again at once.

| Status | Proc effect | Lingering | Resist |
|---|---|---|---|
| **Bleed/Hemorrhage** | 15 % max HP + 100/200 (bosses ~10.5 %) | instant burst | Robustness |
| **Frostbite** | 10 % max HP + 30, **−20 % absorption**, slowed stamina regen | 30 s (fire clears) | Robustness |
| **Poison** | 0.07 %/s + 7 | 90 s (6.3 % + 630) | Immunity |
| **Scarlet Rot** | 0.18 %/s + 15 | 90 s (16.2 % + 1350) | Immunity |
| **Sleep** | enemy: sleeps + open to crit; player: stun + FP drain | ≤60 s / until hit | Focus |
| **Madness** | 15 % HP + 100 + FP drain (Tarnished only) | instant | Focus |
| **Death Blight** | **instant death** (mostly player) | — | Vitality |

Sources: [Status Effects](https://eldenring.wiki.fextralife.com/Status+Effects) · [Hemorrhage](https://eldenring.wiki.fextralife.com/Hemorrhage) · [Scarlet Rot](https://eldenring.wiki.fextralife.com/Scarlet+Rot)

---

## 6. Attacks, verbs & pacing

- **Core attacks:** light R1, heavy R2, **charged R2** (higher MV + stance, hyper armor),
  **jumping** (premier stance-breaker, ~2× stance), **running/dashing**, crouch (stealth +20 %).
  Higher commitment → higher MV & poise damage but longer recovery. **[DM]**
- **Verbs:** guard counter (block→R2), backstab (behind→R1), riposte (parry→R1), power stance
  (dual same-class L1 combos), two-handing (×1.5 STR, more hyper armor — **out-staggers**
  power-stancing). **[DM]**
- **Weapon skills / Ashes of War** cost **FP** (~3–30). **FP pool** by Mind: 10→78, 20→121,
  55→328. **[DM]**
- **Flasks:** Crimson (HP) heals +0 **250** → +12 **810**, starts 3 charges; Cerulean (FP) +0
  **80** → +12 **220**, starts 1. **Shared pool max 14 charges.** Drink ≈ 3 s, full commitment,
  interruptible, no i-frames. **[DM]**
- **Lock-on:** hard lock (R3) shows a reticle dot; soft lock auto-aims within a forward cone;
  right-stick flick switches targets. ER's lock range is large for the open world. **[DM/APX]**
- **Commitment & buffering:** **no attack canceling** through active/recovery — the dodge is
  the escape. A roll can be **buffered during an attack's recovery tail** (the main defensive
  out). ER's buffer is long/generous. R1 chains within ~0.3–0.5 s. **[APX]**
- **HP bars:** **bosses/great enemies show a named bar**; **common enemies show none** — bar
  presence signals "notable fight."
- **Swing timing [APX]:** light R1 ~0.5–0.8 s, heavy R2 ~1.0–1.5 s, charged R2 ~1.5–2.5 s;
  recovery scales with weight class (colossal = multi-second punish windows → they lean on
  hyper armor).

Sources: [Motion Values](https://eldenring.wiki.fextralife.com/Motion+Values) · [Flask of Crimson Tears](https://eldenring.wiki.fextralife.com/Flask+of+Crimson+Tears) · [Stance](https://eldenring.wiki.fextralife.com/Stance)

---

## 7. The KNIGHT enemy class (the shield bearers)

One skeleton reskinned per faction (Godrick / Raya Lucaria–"Cuckoo" / Leyndell / Redmane / Mausoleum /
Haligtree Knight, model c4351–56 "RoamKnight"), with fixed loadout slots: **Knight's Greatsword +
greatshield**, **Partisan + greatshield**, greatbow (swaps to melee up close), mounted. HP runs 657
(Limgrave) → ~4,300 (Elphael) for the same enemy — ~6.5× by region **[DM]**.

### Moveset (greatshield variants)
- **The guard is held while walking AND while attacking.** The approach is a slow guarded stalk; pokes and
  chops are thrown around/over the shield edge with the guard still up. The partisan variant's signature is
  **a multi-hit charging attack delivered with the guard raised** — you cannot trade into it frontally;
  parry it or step off the line. **[wiki verbatim]**
- **The greatsword variant adds a vertical slam with a DELAYED downswing** — "they are capable of delaying
  the downswing"; two authored timings for one silhouette, chosen by AI dice, existing to bait early rolls.
- **Shield bash** — the anti-crowding / anti-circling answer; "dodging to a shielded knight's side/rear
  triggers predictable shield bash counterattacks."
- **Thrust chains resist interruption** ("can't interrupt them while they're doing the triple stabby jab" —
  hyperarmor on the string).
- **ENEMY GUARD COUNTER:** "Those with a shield can perform a Guard Counter **if an attack lands on their
  shield**" [wiki.gg, Leyndell] — hitting the raised shield triggers a riposte poke. The documented player
  loop: "hitting their shield so they counter, then blocking their counter to land a counter yourself."
- What beats them, per the wikis: guard counters and charged heavies (stance), circling for the back while
  they swing, jump attacks over the board, thrust weapons past the shield edge, kicks/Square Off (guard
  crush), status through the shield. "Light attacks won't break the Godrick Knight's poise; a heavy does."

### The elite pair (calibration points)
- **CRUCIBLE KNIGHT** (stance **80**, all melee parryable, backstab-immune, 35 % physical negation): the
  patience duel. Sword slash strings run **1–4 hits, variable** — no memorizable punish count. The overhead
  reads on WHICH SIDE the sword rises (one side is slower — same picture, two clocks). The **shield bash
  fires only while he is blocking** — the shield is an attack trigger, not a wall; "when he raises its
  shield, it will almost always shield charge you." Ground-drag rising slash (sparks off the turf ARE the
  tell). Phase 2's tail sweep exists to punish YOUR punish window. Community verdict both ways: "fighting
  this guy is all about patience" / "for almost every attack you get on them, they get one on you back."
- **BANISHED KNIGHT** (stance 65–75, backstabbable): the frenetic mirror — longer strings, hyperarmor
  mid-combo, but systemically soft (full crits, bounces off greatshields). Its stab tell is **the shield
  rising above normal guard height** — the tell on the OFF arm, a silhouette change, not the weapon.
- **TREE SENTINEL / DRACONIC TREE SENTINEL** (stance 80, crit-immune): the giant-scale grammar. Attack
  choice is **positionally deterministic** (behind → backward swipe; shield side → slower, safer moves —
  "stand on the shield side" is a learnable rule); phase turns are announced by one fixed signature move
  (Shield Crush at exactly 60 % HP); the only fast no-windup hit is a close-range proximity tax; everything
  huge pays with "extremely telegraphed, lengthy recovery."

### The knight brain (datamined structure)
ER enemy combat AI is per-enemy Lua over ~150 GOAL primitives — **distance bands + dice odds**, not
utility AI **[DM]**: `NPCStepAttack(r1Range, r2Range, ifBothR1Odds)` picks light vs heavy by range with an
odds split; `ContinueKeepDist(closeGuardOdds, farGuardOdds)` is the probability of walking with the shield
up per range band; `SidewayMove` strafes; `StepSafety(front/back/left/right priorities)` picks the evasive
step; `ComboAttack/ComboRepeat/ComboFinal` chain strings; `GuardBreakAttack` selects shield-crushing swings
when the TARGET is blocking; **per-attack `turnTime`/`turnFaceAngle`** governs windup tracking (rotate
during windup, freeze on release; some held attacks are given weak tracking on purpose so strafing is a
rewarded answer). Enemy guard is parameterized: per-damage-type block cut rates, **enemy stamina as the
guard bar** (`stamina`, `staminaRecoverBaseVel` — empty it and the guard smashes open), a **guard ARC**
(`guardAngle`, up to 180°) outside which the block is ignored, and `guardLevel` vs attacker guard-crush
rank deciding the recoil animation. Stance (`superArmorDurability`) regenerates at ~13/s after a
`stance/13`-second delay — 80 stance ⇒ ~6 s of pressure window **[DM]**.

### The animation contract (why their attacks read)
FromSoft attacks are **five phases**: Opening Pose (telegraph silhouette) → Attack Signal (weapon starts
its arc — hitbox still dead) → Attack (**2–4 active frames** on a Black Knight swing) → **held End Pose**
→ Return (the punish window). Hard floors from the DS3 anatomy: **Signal + Attack ≥ 340 ms**; an End Pose
used as a bait ≥ 240 ms **[DM]**. Measured ER shape: ~15 frames of anticipation pose, ~6 frames of travel,
recovery 3–4 frames mid-combo but **23–24 frames at combo end** — the whole string is one commitment, the
debt paid at the finisher. The delayed hold ("raise weapon, wait a full second, strike instantly") converts
dodging from reflex to timing; **the release cue is the weapon starting to move**, plus micro-cues (the
Crucible sword-tip flicks vertical just before the swing; a front-foot stomp before a leap). Weight is the
RATIO — slow labored lift, near-instant strike, mass-scaled recovery, follow-through that carries the body,
ground shockwave where the mass went. Rules of thumb: **one unique gross silhouette per attack** (shield up
/ sword overhead / knee up / hunched behind shield) plus one weapon-local release cue; oversized hitboxes
("several times the weapon model") are deliberate. Mocap lineage is kabuki: poses struck and HELD;
locomotion captured **to a metronome**.

Sources: agents' multi-source sweeps over [Fextralife knight pages](https://eldenring.wiki.fextralife.com/Godrick+Knight) ·
[wiki.gg knight pages](https://eldenring.wiki.gg/wiki/Leyndell_Knight) · [Crucible Knight](https://eldenring.wiki.fextralife.com/Crucible+Knight) ·
[Banished Knight](https://eldenring.wiki.fextralife.com/Banished+Knight) · [Tree Sentinel](https://eldenring.wiki.fextralife.com/Tree+Sentinel) ·
[Draconic Tree Sentinel](https://eldenring.wiki.fextralife.com/Draconic+Tree+Sentinel) · [soulsmodding AI goals/params](http://soulsmodding.wikidot.com/elden-ring-ai-goals-params) ·
[Paramdex NpcParam/NpcThinkParam defs](https://github.com/soulsmods/Paramdex) · [DS3 attack anatomy](https://www.gamedeveloper.com/game-platforms/anatomy-of-an-enemy-attack-in-dark-souls-3) ·
[Demon's Souls mocap interview](https://blog.playstation.com/2021/03/26/what-demons-souls-can-teach-stunt-performers-about-human-movement/) ·
[ER frame-by-frame comparison](https://medium.com/@nesterenkodmitry96/frame-by-frame-elden-ring-vs-ac-valhalla-dash-and-enemy-attacks-7ff7138b718e)

