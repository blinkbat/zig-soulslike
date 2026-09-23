# Authoring daily schedules

Open **Events** in the editor and choose **+ schedule**. The new schedule is empty and has no assigned units.
Add a time slot with **+**, choose its start/end hours and orders, then use **lay route** to click points on the
ground. **Backspace** removes the last point; **Enter** or **Esc** returns to Events. Existing points remain when
you resume laying a route. You can also edit coordinates, move a point earlier, remove points, or clear a route.

Select a creature or folk in **Units** and choose its schedule above the delete button. Several units can share
one schedule. Separate schedules allow different starting times, routes, and orders. Renaming a schedule keeps
its assignments; deleting one detaches its units without deleting the units.

The editor supports 32 schedules, 8 time slots per schedule, and 8 route points per slot. Schedules and
assignments save with the map and participate in editor undo/redo.

## Time and orders

Hours use a 24-hour clock: `0` is midnight, `12` is noon, and `.25` means fifteen minutes. An end hour before
the start crosses midnight: `22 → 3` runs from 10 pm until 3 am. The end time is exclusive. Equal start and end
times mean all day. The first matching slot takes priority when slots overlap; **earlier priority** changes
that order. Outside all slots, or with the schedule disabled, units resume their usual orders.

| Orders | Behavior |
| --- | --- |
| Hold | Walk to the first point and remain there. Without a point, stay where the slot began. |
| Travel once | Follow the points in order, then remain at the last one for the rest of the slot. |
| Patrol | Walk the route back and forth. Use at least two points. |
| Roam near post | Wander around the first point, or the position where the slot began if no point is authored. |
| Roam freely | Wander without a fixed tether, using the creature's ordinary roaming behavior. |

Movement uses each unit's existing speed, gait, collision and terrain rules. Waypoints do not make impassable
terrain passable; lay routes through connected, walkable ground. **Focus route** moves the editor camera to the
first point. The selected route appears in the world with its starting point highlighted.

**Peaceful** lets creatures follow their orders without attacking on proximity. Being attacked still rouses
them. Combat takes priority over changing scheduled orders; after combat settles, the current slot applies.
Folk continue a scheduled walk when approached and stop for an actual conversation.

A creature's **presence** setting is independent of its movement schedule. For example, a night-only shade
still needs night or **presence: all hours** to walk a route. Rooted creatures and brood sacs cannot receive
movement schedules.

## Checking a schedule

The Events panel shows which slot matches the current editor clock. **Set clock** selects the displayed slot's
start; **F5** plays from the editor camera at that hour. The editor's `,` and `.` controls also change the hour.
Units walk to the route from their current positions when a slot begins; changing the clock never teleports them.

All schedule records and participant assignments are authored in the map. Event-specific actions such as bell
calls and opening gates are outside the movement schedule.

```text
schedule: road_rounds enabled=1
  shift: 6 18 patrol passive=0 wp=-8,0 wp=8,0
  shift: 22 3 travel passive=1 wp=8,0 wp=8,12
foe: tolling_hollow -8 0 0 1 0.3 schedule=road_rounds
npc: merchant -6 0 0 1 0.4 schedule=road_rounds
```

The hidden screenshot bench is `--shot --shot-only schedule_study`; it builds its example in memory and never
writes a playable map.
