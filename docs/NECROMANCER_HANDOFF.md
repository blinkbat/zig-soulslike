**Opus handoff: finish the necromancer model and animation pass**

Finish this unit autonomously, including implementation, meaningful tests, and inspection of fresh renders. The owner asked for fluidity, readable models and animations, and fair hitboxes, perfected one unit at a time. This handoff is for the necromancer only.

**Starting state**

- Read the repository `AGENTS.md`, especially “The necromancer,” “The hero rig,” and “Build & verify,” then `docs/MODEL_ANIMATION_PASS.md`. Do not repeat the completed units' audits.
- `src/foes/necro.zig` has no working-tree changes at handoff. The baseline audit and `necro_study` harness already exist. Inspect `shots/necro-baseline-contact.png`; individual `shots/necro_study_*.png` provide larger crops. These are baseline images, not proof of completed work.
- The last recorded full suite was 1375/1375 after the delver and shared capsule-normal correction. This is historical evidence, not a fresh result for the current tree.
- The tree contains substantial uncommitted work. Check fresh diffs before editing. Concurrent work includes audio, druidess, fungal duo, and documentation; preserve it. Do not reset files, commit, push, or create branches.
- The small default hero light and higher skeleton shields are already done. Leave them intact.

**Keep the existing creature**

It is a tall, narrow skeletal caster in a dark blue dragging robe, holding a crooked staff in its RIGHT hand and casting with its LEFT. Preserve its stature/width relationship, cold palette, cooldowns, damage, corpse rules, and keepaway role. It never melees. No new abilities or audio family are needed.

The corpse is held open by `game.markVigil`; the necromancer reports one `raised` edge and `raiseAt`; `game.applyRaises` owns resurrection. A corpse is raised once, without restoring its shield. Raise commits its corpse position at gather start and remains planted. Frost currently captures the hero's POSITION when `lay(hero)` runs at cast completion, then remains fixed at that position and height. Preserve that timing; do not silently change it to a gather-start target. A laid ring survives the caster's death and bills once. Walking clears the normal-sized ring before its fuse expires.

No hitstop, time dilation, input reading, or smoothing of mechanical movement. Lean through the spine/chest with grounded legs. Reactions must be large, continuous, overshoot, and settle. Keep seeded irregularity and subtle relief. The dragging cloth may pass slightly below the sole plane by design; feet and rigid kit require separate clearance checks.

**1. Repair the model and its attachment geometry**

Start with `hemMesh`, `chestMesh`, `abdomenMesh`, `sleeveMesh`, `forearmMesh`, `handMesh`, `staffMesh`, and `staffSeg` in `src/foes/necro.zig`.

- The baseline robe reads as stacked rigid sections. `hemMesh` joins three independently generated skirts with 10, 11, and 13 sides. Replace these with a continuous folded surface using shared angular samples between rows, restrained vertical folds, and an irregular dragging hem. Preserve the narrow silhouette and deliberate overlap at articulated waist/chest joints. Inspect the assembled robe through bends; a good isolated skirt is insufficient.
- Reuse the approach in `kobold.clothLoft`. If sharing it, extract a small helper into `src/props/propart.zig`, parameterized by stature and palette, and leave the kobold output equivalent. Its rings are `[x, y, z, radiusX, radiusZ]` in stature-relative units, with the bottom row first. Avoid duplicating a second cloth implementation. Run kobold checks and inspect a priest render if that shared path changes.
- The palm starts below and forward of the wrist without a connecting wrist mass. Close that anatomical gap, retaining slim rounded bones and distinct fingers. Check both hands close from four sides. Improve skull and joint tessellation where visible; keep the existing identity and restrained ornament.
- The curved staff mesh does not follow the straight endpoints reported by `staffSeg`, and its generated curve drifts away from the nominal grip. Generate one deterministic staff path shared by mesh, grip calibration, and measurements. Anchor its interpolated grip to `(0, FIST_Y, FIST_Z)`; use actual path endpoints for `staffSeg`. Preserve fixed arm lengths and rotate about the real grip. Keep the ferrule low in carry/raise and deliberately lifted for frost. Avoid alternating wood colors segment by segment.
- `HELD` is parented to the right wrist. Keep staff construction after that arm's world matrices are ready. Raylib matrix multiplication applies its first argument first. `staffTilt` uses 180 degrees as plumb; the arm and torso rotations both affect the final measured lean.

Check and render the model before progressing to motion. Use the corrected shared `gfx.Builder.ringBand` normals already in the tree; do not reintroduce the old radial-only capsule/taper normals.

**2. Replace the cast/recovery interpolation with continuous motion**

`setRaiseWind`, `setRaiseUp`, `setFrostWind`, and `setFrostCast` currently interpolate a few fixed poses. `setRecover` repeatedly lerps the current output toward carry by `e * 0.22` per frame, so recovery changes with frame rate.

- Use `core/anim.zig` (`anim.Pose`, keyed tracks, `SpringBank`) as in the completed units. Author gather, held anticipation, release gesture, carry-past, rebound, and settle for each existing cast. Keep their existing mechanical durations and release edges.
- Order channels to produce torso-to-arm-to-hand/head lag. Seat the bank at the carry pose in `spawn`. Advance it once per update; `pose` and drawing must not advance simulation. Avoid recursively smoothing targets as well as spring outputs.
- Include light/heavy reactions and recovery in the same continuous pose system. Interrupting any phase must retain the current pose and velocity. Route recoil through the torso, brace the knees, and let the staff follow without detaching or burying its ferrule.
- Preserve the existing hem lag and overshoot. Its Euler spring should be checked at 30/60/144 Hz; use the shared spring implementation if needed. Keep cloth secondary motion later than the torso. Retain the shared distance-driven humanoid gait and articulated upper body.

Readability target: corpse-directed raise and frost should be distinguishable by silhouette before release; the long raise has a visibly held tell; the release gesture coincides with the event, despite spring lag; recovery visibly crosses rest before settling.

**3. Finish the retreat hop and interruption behavior**

The current leap samples `LEAP_SPEED * sin(pi*u) * dt`, which makes travel frame-rate-dependent; `airborne()` always returns false. The root receives `hop` while the legs still use a ground-based solve. Interrupting the leap changes state without completing the hop's vertical motion.

- Integrate the existing speed curve across clamped partial takeoff/landing frames. Keep the authored duration, peak speed, height, navigation, and retreat choice. Test unblocked travel at multiple frame rates before considering any tuning.
- Give flight a proper tucked leg pose with fixed bone lengths. Resume planted soles with a visible landing compression/rebound. Reuse `hero.armTo`/`mathx.twoBone` where appropriate; `twoBone` returns `joint` and `end`.
- Preserve height and vertical velocity when staggered or killed in flight, then land continuously. `shroom.zig` and `brood.zig` contain completed examples. Audit `airborne`, root restraint, and death posing together so a visual hop cannot freeze aloft or teleport down.
- Derive pose-sensitive measurements such as `topWorld` from the posed body where necessary. Verify staff, hands, skull, knees, and feet through takeoff, apex, landing, recoil, and death.

**4. Align spell events and hit volumes with what is shown**

- `update` currently emits raise/bloom or lays frost before `pose` and `tryHit`. Reproduce a blade interrupt on the exact completion frame. Defer new spell events and their sound/FX until incoming-hit resolution confirms the cast survived. Ensure the external `raised`/`laid` edges are still exactly one frame.
- Keep already-laid sigils independent: interrupting or killing the caster must not cancel an old ring, its fuse, or damage due that frame. Do not clear all outgoing damage indiscriminately. Preserve cooldown spending for interrupted gathers.
- Sample hand-attached gather/release FX from the final current pose. Preserve frost's ground height at the target and its existing commitment semantics.
- `tickSigil` tests only XZ distance, giving the ring unlimited vertical reach. Bound contact using the visible ground burst and the existing hero capsule conventions. Verify hits on the marked floor and misses on a separate upper/lower floor without casually changing intended jump interactions.
- Audit incoming blade coverage: the current chest-centered `HURT_R` sphere can disagree with a thin, articulated body. Reproduce visible misses/false positives before changing it. If needed, reuse `foe.hullTouches` with a few posed body volumes and a conservative broad phase that encloses them. Check head/lower-body coverage, empty space beside the robe, and swept blades. Preserve `foe.reached`/`wounded` latches and damage rules.

**5. Verify with the existing harness, then close the unit**

Current filenames are `necro_study_{side}_{mode}_{frame}.png`, where sides 0–3 rotate the subject by 0/90/180/270 degrees while the camera stays on the lit bearing. Modes:

| Mode | Action |
| --- | --- |
| 0 | Idle/carry |
| 1 | Raise |
| 2 | Frost |
| 3 | Retreat hop |
| 4 | Heavy reaction |
| 5 | Actual lateral drift |
| 6 | Death/dissolve |

The existing study is normal-sized only, and `unitStudyViewFrame` currently draws FX only for Rooted and Delver. Extend it narrowly for necromancer FX. Add a separate scene framing both caster and distant ring through the full 2.70-second fuse; the existing frost strip ends too soon and frames only the body. Keep close hand/staff views as well. Add light reaction, interrupted cast/hop, complete settle, and size variants where needed. Pin the hour, keep the subject lit, include the full swept staff, and take captures before `endDrawing`.

Use PowerShell from the repository root, checking each exit code:

```powershell
.\check.cmd
& ..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe build test -Dtest-filter=necro --summary all
& ..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe build --prefix zig-out-dev
& .\zig-out-dev\bin\zig-soulslike.exe --shot --shot-only necro_study_1_1
```

Use narrow shot filters during iteration; `necro_study` selects the whole unit. Do not launch an interactive game. Confirm output filenames and timestamps before inspecting images. Crop the hand/grip, elbow, and hem instead of judging those parts from a distant contact sheet. Inspect both individual poses and ordered motion strips, plus a gameplay view for actual combat readability.

Add meaningful regressions for fixed-length/grip geometry, phase and interruption continuity, recovery/flight at 30/60/144 Hz, scale multipliers x0.5/x1/x1.8, release-frame cancellation, old-ring survival, vertical separation, and any corrected hurt coverage. Exercise real `update` calls rather than only assigning ideal poses. Retain all existing corpse, fuse, walk-out, staff, hem, and elbow tests. The normal-sized ring's walk-out guarantee is already authored; larger ring behavior must be measured, not claimed from that test.

Once focused checks and visual inspection pass, run the full suite once:

```powershell
& ..\.zigtoolchain\zig-x86_64-windows-0.14.1\zig.exe build test --summary all
```

Completion means the robe reads as cloth, hands and staff are physically attached, tells and releases read clearly, recoil and landings settle continuously, hits match the visible action, existing mechanics pass, and fresh four-sided/motion/FX shots have actually been inspected. Update `docs/MODEL_ANIMATION_PASS.md` with the final changes, exact verification results, image paths, and any remaining limitation. Do not mark the unit complete on a clean build alone.
