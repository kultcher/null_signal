# Encounter Templates

Encounters are the building blocks for longer sequences and, later, proc-gen:
a small group of signals with a known role and threat profile. Each template
is **mostly fixed elements plus at most one wildcard** whose behavior or
position varies per placement. Fixed elements keep a template recognizable;
the wildcard keeps repeats from being memorized and usually decides its threat
profile.

## Code

| File | Role |
| --- | --- |
| `Scripts/Encounters/EncounterTemplate.gd` | Base `Resource`: `generate(run, anchor_cell, rng, prefix)`, `check_fit(layout, anchor, length)`, mirroring and facing helpers |
| `Scripts/Encounters/EncounterInstance.gd` | One placement: spawn dictionaries (ready for `get_spawns()`), `roles` (system_id -> role), `wildcard`, `stop_points`, footprint |
| `Scripts/Encounters/Templates/*.gd` | The four templates below; exports carry the tuning |
| `Scripts/Encounters/EncounterLibrary.gd` | `make(id, difficulty)` / `all()` |
| `Resources/RunData/AuthoredRuns/EncounterGalleryRun.gd` | All templates strung along a hall, watched doors between sections |
| `Tests/encounter_template_test.tscn` | Generation, fit, wildcard variety, determinism, threat profile over 12 seeds |

Templates are Resources, so a tuned variant (e.g. a harder corridor) can be
saved as a `.tres`. Placement is relative to an anchor on a straight stretch of
route at `route_lane` (2). Every random choice comes from the passed `rng`, so
a seed reproduces a placement exactly. `allow_flip` mirrors top/bottom.

System ids are `<prefix>_<role>` (e.g. `camera_0_cam_fixed`), so roles survive
into the analyzer and viewer.

## Templates

Tuning follows the tutorial (and Night Audit for guards). Threat profiles are
from `ReachAnalyzer` over the gallery seeds.

### Watched door (`watched_door`)
- Puzzle-locked door on the route (puzzle from `puzzle_pool`, difficulty).
- Wall camera on the outer lane just before the door, aimed at the spot where
  the runner waits.
- Wildcard: none. Tagged `transition`: use it as the standard seam between
  sections (door on the boundary).
- Stop point: `blocker` just before the door.
- Profile: door certain (blocker); camera certain and covering the waiting
  spot, so a slow solve costs heat.

### Camera corridor (`camera_corridor`)
- 4 panning cameras alternating between the outer lanes, 3 cells apart
  (tutorial cam_03..cam_06: 20 deg, 1.2 cells, 3.5s dwell at each end).
- Wildcard: one stationary camera on the route (tutorial cam_07), inserted at
  any slot in the sequence (before, between or after the pans). Gets Bouncer
  from difficulty 2.
- Profile: pans possible; the wildcard certain.

### Drone patrol (`drone_patrol`)
- 2 drones on vertical patrols across the route, 2 cells apart (tutorial
  c_drone_02/03: lanes 0-3 and 1-4, 0.25 cells/s, 3s dwell, 60 deg / 0.8).
- Wildcard: a third drone placed before or after the pair, either a long
  horizontal patrol one lane off the route (tutorial drone_02, 6 cells) or a
  small square over it (drone_01, lanes 1-3).
- Profile: all possible.

### Guard patrol (`guard_patrol`)
- 2 guards on dodgeable patrols: a square loop over lanes 1-3 and an L that
  ping-pongs (down across the route, then along the far wall). Each crosses the
  route only on its vertical legs.
- A reveal camera between them on the wall, looking along it (never at the
  route). Both patrols stay inside its guard-reveal range (3.5 cells), so
  connecting to it is how the player reads the room.
- A disruptor (1-cell range) at the middle of one guard's patrol.
- Wildcard: none.
- Profile: guards possible with low walk-through odds (~30%); camera never.

## Fit

`check_fit()` checks the footprint against a layout:
- a straight route at `route_lane` across the footprint;
- one section only, unless tagged `transition`;
- every `required_lanes` lane inside a room (default 0, 2, 4).

It returns a list of problems (empty = fits). This is the hook for geography
requirements once walls block sight (see the LOS notes below).

## Stop points and section entry

- `EncounterInstance.stop_points`: where the runner waits, `{cell, lane,
  kind}`. Today only `blocker` (the watched door). Reserved: `cover`.
- `FacilitySection.entry` (`&"hot"` default, `&"safe"`), set with
  `section(...).entry(&"safe")`. Not acted on yet; reserved for the hold +
  relay preview in `FutureDirections.md`.

## Findings from building these

- **Walking pace always gets grazed by panning cameras.** At base speed the
  runner is in a sweep's band longer than one sweep cycle, so every walk-through
  is seen at some point (the tutorial's cameras behave the same). The analyzer
  now reports **exposure** (mean seconds seen per pass) next to hit chance:
  tutorial cam_05 is a 0.8s graze at walk, cam_02 a 3.1s look. Dodging cleanly
  needs hustle or a hold; with instant camera detection, a graze still costs a
  little heat.
- **Cone patrollers looked backwards** when following their movement (cones
  point to -x). Fixed via `DetectionComponent.facing_for_direction()`. Basic
  drones weren't affected (they run their own sweep); escalation spawns and
  any future cone patroller without a sweep were.

## Next steps

1. Done: the gauntlet can run encounter templates (see
   `CalibrationGauntlet.md`).
2. Viewer: seed field + Regenerate for generated runs; encounter footprints as
   an overlay.
3. First generator pass: fill an authored layout with templates under a
   pressure budget, using `check_fit`, `ReachAnalyzer` and `CostTable.fit`.
4. Geography requirements once LOS lands: occluder segments from rooms and
   enclosure props (glass / solid / smart glass), "side room with an opening
   onto the route", sightline length, cover props. Templates gain those as
   requirements; their format doesn't need to change.
