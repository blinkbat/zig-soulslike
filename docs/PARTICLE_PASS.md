# Particle pass

Direction: fuller clouds, distinct elements, stronger contact feedback and blood
spatters, kept local and restrained. Damage, attack clocks and hit volumes are
unchanged; no hitstop.

- The particleart module builds one deterministic atlas: grain, shaded smoke,
  spores, flame, frost, sparks, chaos, blood, contact flash and glow, with four
  variants each. No external image assets.
- Particle.style selects a shape. Existing emitters inherit grain, smoke,
  spark, blood or glow from their existing properties. Alpha particles sort
  back to front within their pool; additive light follows. Both use the same
  atlas and retain depth testing without depth writes.
- foe.drawCloud(CloudLook) layers 48 seeded lobes/motes through a volume.
  Growth, density, palette and lifetime come from the caller. Used by the
  sporeling cloud, knight gas, fungal magus breath and lingering mist, sleep
  pollen and the low vapour above brood venom.
- foe.drawAura supplies animated small volumes around fungal projectiles and
  the mushroom mage's cupped flame. elemfx supplies flame tongues and smoke,
  falling frost with fog, short electrical streaks and contracting chaos.
  Chaos can curl its particle velocity without reading any actor state.
- foe.contactFlash shares hit/block/parry accents. The strongest is the
  successful parry, lasting 0.12 seconds. Existing material debris stays with
  its emitter; blood gets irregular droplets and seeded ground spatters that
  retain their size and fade over 1.4 seconds. Wet-ground exclusions remain.

Verification: check.cmd, zig build test, and the direct
--shot --shot-only particles_study stage. The stage captures elements, contact
effects, blood landing and a spore cloud through its lifetime, beside the hero
at actual terrain height. Settle the hero after placing him before reading his
hand transforms: the equipment crossfade can otherwise retain the old pose.

Final check and normal build passed; 29 study frames were captured and the
effect families inspected. Full suite: 1409/1410 passed. The remaining failure
is the concurrent desert palette's spine/cactus contrast assertion in
props/propdesert.zig, outside this pass. A review sheet is in
shots/particle-pass.png.
