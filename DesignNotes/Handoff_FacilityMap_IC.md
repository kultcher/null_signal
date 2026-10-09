# Handoff: Facility Map + IC/Action Resolver Pass

Branch: `claude/game-env-simulation-redesign-ig7u4z` (based on `main` @ "Repo management").
Detailed authoring reference for the map lives in `DesignNotes/FacilityMap.md`;
this doc is the "what changed and why" summary.

---

## 1. Top-down facility map (replaces the timeline strip)

### Core idea

The game still runs on a **1D time horizon**: the runner's progress along a
route drives everything. What changed is how that is presented and authored:

- The 5-lane strip is now a **top-down floorplan** (rooms, walls, doorways,
  props). Lanes are real vertical positions (90px apart, was 54px).
- The runner follows an **authored route** (waypoints), not a fixed lane.
  Speed is measured in cells of *path length*, so turns and dodges cost time.
- `TimelineManager.current_cell_pos` is still the **runner's x on the map**, so
  everything keyed on cells (tutorial triggers, `cell_reached`, range checks,
  Faraday, distractions) works unchanged. Distance along the route is
  `path_progress`; the runner's lane is `runner_lane_pos`.
- `TimelineManager.map_mode` (default `true`) switches back to the old strip.

### Feeds (sections)

A run is split into **feed sections**, one framed camera view each:

- The view follows the runner (1 cell from the left edge, 8 cells across,
  ~47s lookahead) and **holds** once the section's end reaches the right edge,
  so the runner walks into the last obstacle on a still frame.
- When the route leaves the section, the feed **cuts** (static overlay +
  `FEED 02 // LABEL`) and comes back on the next section.
- Signals belong to the section their spawn cell falls in and only exist while
  that section is shown (next-section signals can't be pre-scanned).
- Runs without sections get one default section with a straight route along
  lane 2, which reproduces the original behaviour.

### Authoring (in each `RunDefinition`)

```gdscript
func get_sections() -> Array[FacilitySection]   # feeds + route waypoints
func get_rooms() -> Array[FacilityRoom]         # floorplan
func get_spawns() -> Array[Dictionary]          # signals, as before
func is_escalation_enabled() -> bool            # default true
```

- `section(id, start_cell, end_cell).label(...).path([Vector2(cell, lane), ...])`
- `room(id, start, end).lanes(top, bottom).opening(side, from, to).prop(..., label, model).exterior().in_section(id)`
- `spawn(...).model(&"nanofab")` for signal hardware wireframes (otherwise
  inferred from id prefix: `coolant_vent_*`, `nano_fabricator_*`, ...).
- Doorways are cut automatically wherever the route crosses a wall.
- A corner = route that leaves the map edge; the runner fades out, then the cut.

### New/changed files

| File | Role |
|---|---|
| `Scripts/Facility/FacilityLayout.gd` | Rooms, sections, route maths (`sample_position`, `progress_at_cell`, `project_to_path`) |
| `Scripts/Facility/FacilitySection.gd` | One feed: cell range + route waypoints |
| `Scripts/Facility/FacilityRoom.gd` | Room data (extent, openings, props, section) |
| `Scripts/Facility/facility_map_layer.gd` | Draws floors, walls, props, route line, feed label; clips to map |
| `Scripts/Facility/feed_switch_overlay.gd` | Feed-cut static effect |
| `Scripts/Facility/WireframeModels.gd` | Wireframe model library (props + signal hardware) |
| `Scripts/timeline_manager.gd` | `map_mode`, route state, section-aware view, spatial conversions |
| `Scripts/signal_manager.gd` | Positions via conversions; per-section visibility |
| `Scripts/grid_layer.gd` | Map-sized backdrop; runner placement/fade; lane grid only as fallback |
| `Resources/RunData/RunDefinition.gd` | Room/section builders, `model()`, `is_escalation_enabled()` |
| `Scripts/escalation_manager.gd` | Honors `is_escalation_enabled()`; panel follows map height |
| `Scripts/tutorial_manager.gd` | `set_runner_cell()`, map-mode dialogue wording, docked dialogue |

**Spatial API** (use these, don't compute screen positions by hand):
`cell_to_screen_x`, `lane_to_y`, `cell_lane_to_screen`, `screen_x_to_cell`,
`get_runner_screen_pos`, `get_map_rect`, `set_runner_cell`,
`get_current_section`, `is_cell_in_current_section`.

### Tutorial port

- Two feeds: yard + security hall (route swings in past the van, turns down a
  service stair = the corner), then everything from the service corridor on
  (runner hugs the top wall past `cam_04`, which takes it out of reach).
- Encounters retuned for wider lane spacing (vertical patrollers 0.25 cells/s,
  some longer cones), checked against the old layout with the exposure sim.
- In-game tutorial dialogue docks to the right of the terminal in map mode;
  cutscene dialogue stays centered.
- Escalation disabled for the tutorial (heat still builds).
- Main scene (`run_main.tscn`) runs the tutorial.

### Gotchas

- `Vector2` is 32-bit: interpolate long route segments in scalar (64-bit) math.
  This caused jerky runner movement on runs with no sections (fixed).
- Patrol/sweep timing starts when a signal comes on screen, so threat phase
  relative to the runner varies with hustle/holds. Judge exposure over
  multiple trials (see Tests below). Per-section clocks would fix this.
- Codex popups pause the scene tree on first full scan of a new IC type.

---

## 2. IC expansion

Five new modules (`Scripts/ICModules/`), registered in
`RunDefinition._create_ic_module`, each with codex entries in `Resources/Codex/`:

| IC | Behavior | Tiers 1-4 |
|---|---|---|
| Tripwire | Heat spike when the *player* disables it | +600/900/1200/1600 |
| Siphon | Heat bleed per second while a session is open | 40/60/90/130 per s |
| Heartbeat | Watchdog pulse; downed node restored on the beat + tamper heat | 9/7/6/5 s |
| Tether | Open session blocks commands/ACCESS on other signals; early-disconnect heat at higher tiers | +0/300/500/800 |
| Shy | Scan data scrubs itself after a full scan | 8/6/5/4 s |

`Resources/RunData/AuthoredRuns/ICTestRun.gd`: straight corridor, one bay per
new IC, escalation off. Point `RunManager.level_script_path` at it to try it.

Note: `ic_master.md` has two different "Tether" ideas; the implemented one is
the expansion-section version (exclusive session), not the NEWEST-list one
(linked signals).

New `ICModule` helpers: `_queue_heat()`, `_notify()`, `_is_player_action()`.
`ActiveSignal.reset_scan_progress()` and `signal_entity.rebuild_tooltip()`
support scan-wiping IC.

---

## 3. Action resolver / command dispatch changes

`Scripts/Autoload/ActionResolver.gd`, `Scripts/Autoload/CommandDispatch.gd`:

1. **`resolve_action()` is now truly synchronous.** Previously, if called while
   the queue was draining it just enqueued and returned a PENDING action;
   callers (terminal commands, scan starts) read that as a result. Now it
   resolves immediately (nested), including the follow-ups it queues.
   `enqueue_action()` is unchanged (still deferred, for system/IC actions).
2. **Session observers.** IC on signals with an *open terminal session* now get
   `process_external_action` / `postprocess_external_action` for actions aimed
   at other signals, and can veto them. Tether uses this; it also enables
   future session-scoped IC (Chorus, Monitor, Repeater...).
3. **Command output across follow-ups.** KILL -> DISABLE -> ADD_HEAT share the
   root command's context. Successful steps now *append* log lines (they used
   to overwrite), failures replace the log with the failure reason, and a
   failure can't be flipped back to success by a later step.
4. **Explicit-target commands** (`KILL cam_02`) switch the terminal session
   only *after* the action succeeds, so IC can veto the switch. Failed
   commands and failed ACCESS (including click-to-connect) now report in the
   session the player typed into instead of being silently dropped.
   Behavior change: a failed `KILL other_signal` leaves you where you were.
5. `ActionResolver.debug_logging` flag for the per-action console trace
   (default on).

### Known kinks not changed

- Bouncer's timer starts at ACCESS (before the connection banner finishes);
  Trace and the new IC start after it.
- IC `on_connect` doesn't fire when switching back to an already-open tab
  without the connection banner (re-clicking the signal does replay it).
- Every IC sees all system actions aimed at its host (heat, enable, ...), so
  modules must filter by source; use `_is_player_action()`.
- Postprocessors run even when the core effect failed; modules must check
  `was_successful()`.

---

## 4. Headless tests (`Tests/`)

Run with Godot 4.7 from the project root (`--headless`; screenshots need a
display or `xvfb-run` with `--rendering-driver opengl3`). Do one
`--headless --editor --quit` import pass first on a fresh checkout.

| Scene | What it does |
|---|---|
| `res://Tests/ictest.tscn` | Drives the 5 new IC via real commands/scans/timers; prints PASS/FAIL |
| `res://Tests/regtest.tscn` | Regression: explicit KILL, Faraday, Bouncer, Callback, Reboot, error routing |
| `res://Tests/sim.tscn` | Walks the runner through a run, logs per-signal contact time (`-- map=1 straight=0 hold=5 out=user://sim.txt`) |
| `res://Tests/jitter.tscn` | Checks the runner moves every frame (`-- level=res://...Run.gd`) |
| `res://Tests/capture.tscn` | Screenshots at runner positions (`-- prefix=x cells=0.5,12 frames=20`, or `stage=<tutorial stage>`) to `user://shots/` |

Example: `godot --headless --path . res://Tests/ictest.tscn`

---

## 5. Suggested next steps

- Play-test the tutorial and IC corridor by hand (not done in this pass).
- Per-section clocks for patrols/sweeps (deterministic threat timing).
- Exposure overlay / scrub view on the route for level design.
- Branching routes / door shortcuts.
- Walls blocking line of sight; room-aware distraction range.
- Optional: split lookahead windows (0-15s / 15-30s / 30-45s).
