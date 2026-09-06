# Foe feel pass

Scope: fishmen (all three roles), birchwight, salt husk, cinder wake, rotgorger,
blinkbat, and owlbear.

`foe.StrokeMotion` follows keyed load/carry poses with springs. Separate load and
carry channels keep an interrupted arm from passing through its idle pose.
`foe.recoilPose` gives damage reactions a quick overshoot and a settling tail.
`foe.catchMelee` connects these families to the shared parry reservation: the
attack advances into its strike before the catch, with the same contact clock
used for outgoing damage. Both attacker and shield bearings must be valid.

| Family | Changes |
| --- | --- |
| Fishmen | Connected shoulders and waist; trident support grip solved with both arms; leveled thrust; net released from the extending hand; quicker ritual lift; shaman skirt uses `propart.clothInto`. Spearman melee can be parried. |
| Birchwight | Corrected upward lumbar/neck meshes, connected shoulders, finer bark markings, bent crown branches; loaded overhead blow and recoil. Burning haste uses its own shortened clocks. |
| Salt husk | Connected shoulder/waist masses, single-arm clout, fast stagger and deflection, grit on contact. Death fuse remains active. |
| Cinder wake | Connected shoulder/waist masses, single-arm rake, recoil, ash on contact; stroke sound follows the windup. Moving ember trail retains its existing behavior. |
| Rotgorger | Planted legs under torso pitch; jaw/neck recoil; smoother leg joints and visible asymmetric fungal ridge; bite sound and spore contact burst. Carrion feeding retained. |
| Blinkbat | Scalloped, double-sided wing membranes replace rectangular panels; jaw/wing recoil and a dipping bite; posed gather preview seats the shared motion. |
| Owlbear | Connected shoulders, less protruding lichen; distinct single-wing rake and two-wing slam; stone stroke sound, chips, weighted deflection. Both melee moves can be parried. |

`hero.gripShift` is shared by the fishman's trident and the skeletal greatsword.
It fits both grip targets inside the arms' reach without changing their spacing.

Verification:

- `check.cmd`, normal build, full unit suite.
- Contact regressions at 30/60/144 fps and 0.75/1/1.5 scale, including the burning
  birchwight and both owlbear melee moves. Check reservation, unchanged incoming
  animation, catch on the damage frame, no damage, visible recoil, and bearings.
- Trident support grip measured across the entire thrust at three sizes.
- `--shot --shot-only foes_study`: four sides, idle/attack/reaction/death/movement,
  every listed body and fishman role, plus the owlbear slam.
- `--shot --shot-only parry_study`: incoming strike, catch, recoil on both sides,
  including these seven melee families and the earlier parry subjects.

Net throws, the shaman ritual, stone quills, and environmental hazards retain
their existing attack types; this pass adds no melee attacks to the ranged roles.
