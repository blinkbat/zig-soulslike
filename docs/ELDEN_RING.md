# ELDEN_RING.md — the north-star, in numbers

This is the gameplay/systems reference for **zig-soulslike**. Elden Ring (ER) is the north
star (see AGENTS.md); when we say "keep pressure on", "poise", "stagger", "roll", "guard
counter" — this is what we mean, with the real mechanics and the real numbers behind them.

Compiled from heavy multi-source research (Fextralife wiki, Elden Ring Reforged wiki [a MOD
wiki — flagged where used], wiki.gg / Eldenpedia, datamined motion-value & poise spreadsheets,
and community breakpoint threads), cross-verified. Tags: **[DM]** datamined/wiki hard number,
**[APX]** approximate/community-tested, **[disp]** disputed across sources.

> **Frame-data convention (read first).** FromSoft animation data is authored in **30 fps
> units** (TAE ticks) but the game runs at 60 fps. Every "frames" figure on the wikis is a
> 30 fps value — **×2 for on-screen 60 fps frames, ÷30 for seconds.** A "13-frame" medium
> roll is **~0.43 s**, not 0.21 s. Getting this wrong is the #1 porting mistake.

---

## 1. Poise, stagger & stance-break (the heart of our combat)

ER runs **two separately-tracked meters**. We copy both (see [src/combat.zig](../src/combat.zig)).

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

### Critical hits (model only — we don't build these yet)
- Stance-break/parry/backstab → crumple → **R1 executes a critical**. Damage ≈ **2.5×–4×**;
  riposte > backstab by ~25–30%. Dagger riposte **420%** AP, straight sword **345%**, colossal
  **263%**. Weapon Critical stat (÷100) multiplies it: Misericorde 140, daggers/rapiers 130. **[DM]**

### Poise/stance damage dealt by attacks — the tuning that matters
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
  15/30/50. **[DM]** Tune *costs*, not pool size.
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

> **Our roll today** (see AGENTS.md): committed anim + exact travel, but **no i-frames, no
> collision** yet. When we add i-frames, the medium-roll ~0.43 s front-loaded window is the target.

Sources: [Dodging](https://eldenring.wiki.fextralife.com/Dodging) · [Equip Load](https://eldenring.wiki.fextralife.com/Equip+Load) · [Bloodhound's Step](https://eldenring.wiki.fextralife.com/Bloodhound's+Step)

---

## 5. Status effects (buildup model)

**Fill → proc → reset**, with **decay**: each hit adds a flat buildup; at threshold it **procs**
and the meter **resets to 0** (no proc cooldown — can proc repeatedly). Buildup **decays** once
you stop: **base 1/s + the enemy's own 1–10/s** (big bosses shed ~11/s). Resistances (Robustness/
Immunity/Focus/Vitality) **raise the threshold, not reduce the proc.** This is the purest "keep
pressure on" system — spaced hits against a high-decay foe may **never** proc. **[DM/V]**

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
  presence signals "notable fight." *(We deviate here — see §7.)*
- **Swing timing [APX]:** light R1 ~0.5–0.8 s, heavy R2 ~1.0–1.5 s, charged R2 ~1.5–2.5 s;
  recovery scales with weight class (colossal = multi-second punish windows → they lean on
  hyper armor).

Sources: [Motion Values](https://eldenring.wiki.fextralife.com/Motion+Values) · [Flask of Crimson Tears](https://eldenring.wiki.fextralife.com/Flask+of+Crimson+Tears) · [Stance](https://eldenring.wiki.fextralife.com/Stance)

---

## 7. How this maps to zig-soulslike (current build)

Implemented in [src/combat.zig](../src/combat.zig) (`Vitals`), embedded in the hero
([src/hero.zig](../src/hero.zig)) and the toads ([src/frog.zig](../src/frog.zig)), wired in
[src/game.zig](../src/game.zig). We take the **two-meter** model verbatim and simplify the rest.

**The model.** Each character has HP + a **poise** meter + a **stance** meter.
- A hit chips poise by its poise-damage. Poise empties → **light stun** (flinch); poise resets;
  the light break **chips stance**. Stance empties → **heavy stun** (stance-break stagger).
  Heavy attacks also chip stance **directly** (`Hit.stance`) so they break it faster — exactly
  ER's "charged/heavy breaks stance fast." **No criticals yet** (per the brief).
- Both meters **regenerate after a short delay** (poise refills in ~1.3 s, stance ~4.6 s) — so
  you must **keep pressure on** to cascade light → heavy. This is ER's regen-delay tension,
  tuned snappier for a fast prototype (ER enemy delays are ~6–15 s).
- **HP hits 0 → death.** Frog: collapse then despawn. Hero: collapse → **"YOU DIED"** → respawn
  at the start grace.

**Deviations from ER (deliberate, for this prototype):**
- **Floating HP bars over foes** (owner's call) — ER shows bars only for bosses. Bars appear
  over damaged/nearby toads and **flash a gold border while staggered** (our stand-in for ER's
  stance-break crit-sparkle cue).
- **Red screen-edge damage flash** when the hero is hit (ER-style peripheral feedback) — a
  flinch is a **big, unmistakable** event: the whole body snaps back and the screen bleeds red.
- Poise governs flinching in **all** states (not just during our own attacks) — no hyper-armor
  windows yet.
- No stamina, guarding, i-frames, status effects, AR/defense curve, or motion values yet — HP
  and poise/stance damage are **flat per-attack constants**, not AR × MV × defense.

**Current tunings** (all constants, easy to retune):

| | HP | Poise | Stance |
|---|---|---|---|
| Hero | 100 | 55 (~ER Knight 51) | 90 |
| Toad | 46 | **12 (low)** | **26 (low)** |

| Attack | HP dmg | Poise dmg | Stance dmg |
|---|---|---|---|
| Hero light (R1) | 13 | 10 | — |
| Hero heavy (R2) | 27 | 22 | 14 |
| Toad chomp | 11 | 15 | — |
| Toad lunge (slam) | 17 | 26 | 8 |

Stun durations: light **0.46 s**, heavy **1.15 s**. A single light break chips **40 % of max
stance**; regen delay **0.8 s** after the last hit.

**Verify visually** (`--shot`, then inspect `shots/`): `31_frog_flinch` · `32_frog_stagger` ·
`33_frog_death` · `34_hero_flinch` · `35_hero_stagger` · `36_hero_death` · `37_hp_bars`.

**Next (still ER-shaped, not built):** i-frames on the roll (medium ~0.43 s front-loaded),
stamina + guard/guard-counter, criticals off a stance break, hyper-armor windows during
attacks, AR × motion-value × defense damage, and a status buildup (bleed reads naturally on a
bog-toad bite).
