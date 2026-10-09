# Facility Map (map mode)

First pass at replacing the abstract timeline strip with a top-down facility map.

## Model

- The runner follows an authored **route** through the map, split into **feed
  sections**. Speed is measured in cells of path length, so turning or dodging
  costs real time (lane offsets count as lane spacing / cell width = 0.375 cells
  per lane).
- `TimelineManager.current_cell_pos` is still the runner's **x on the map**, so
  everything keyed on cells (tutorial triggers, `cell_reached`, range checks)
  keeps working. `path_progress` is the distance travelled; `runner_lane_pos`
  is the runner's current lane.
- **Lanes are real vertical positions** on the map (`map_lane_spacing_px`, 90px
  vs 54px on the old strip).
- **Camera:** inside a section the view follows the runner (1 cell from the left
  edge, 8 cells across, ~47s lookahead) and **holds** once the section's end
  reaches the right edge, so the runner walks toward the last obstacle on a
  still frame. When the route moves into the next section the feed **cuts**
  (static + "FEED 02 // ...") and comes back framed on the new section.
- Signals belong to the section their spawn cell falls in and only exist while
  that section is on screen.
- `TimelineManager.map_mode` toggles between the map and the old timeline strip.
- Runs without sections get one section with a straight route along lane 2,
  which reproduces the original behaviour.

## Spatial conversions

All screen placement goes through `TimelineManager`:

- `cell_to_screen_x(cell)`, `lane_to_y(lane_pos)`, `cell_lane_to_screen(cell, lane)`
- `screen_x_to_cell(x)`, `get_runner_screen_pos()`, `get_map_rect()`
- `set_runner_cell(cell)` places the runner at the first route point reaching `cell`
- `get_current_section()`, `is_cell_in_current_section(cell)`

`FacilityLayout` (`Scripts/Facility/`) owns rooms, sections and route maths
(`sample_position`, `progress_at_cell`, `project_to_path`).

## Authoring

Sections, rooms and spawns all live in the run definition. Coordinates are
cells (x) and lanes (y).

```gdscript
func get_sections() -> Array[FacilitySection]:
	return [
		section("approach", -3.0, 17.0) \
			.label("LOADING YARD // SECURITY HALL") \
			.path([Vector2(-3.0, 3.6), Vector2(2.2, 2.0), Vector2(16.6, 2.0), Vector2(16.6, 5.6)]) \
			.build(),
		section("interior", 17.0, 82.0) \
			.path([Vector2(16.0, 2.0), Vector2(21.5, 2.0), Vector2(22.3, 0.4), ...]) \
			.build(),
	]

func get_rooms() -> Array[FacilityRoom]:
	return [
		room("security_hall", 6.5, 17.0) \
			.label("SECURITY HALL") \
			.lanes(-0.5, 4.5) \
			.opening("bottom", 16.2, 17.0) \
			.prop(7.6, 9.4, -0.5, 0.35, "RECEPTION") \
			.build(),
		room("stair_landing", 15.4, 17.0).lanes(1.45, 2.55).in_section("interior").build(),
	]
```

- Section cell ranges must not overlap; they decide which signals each feed shows.
- A corner is just a route that leaves the map (e.g. turns down past the bottom
  edge). The runner fades out at the map edge; the cut happens when the
  section's route ends. The next section's route usually starts at its left
  edge (`start_cell - 1`) so the runner walks in.
- Keep the first threat after a cut a reasonable distance in, since the player
  can't see the next section until the cut.
- Walls get doorways automatically wherever the route crosses them; use
  `.opening()` for wider passages and decorative side exits.
- Rooms are drawn by the section containing their midpoint; `.in_section()`
  overrides that (e.g. a landing stub that overlaps the previous section's range).
- Decorative rooms can extend past the map edges; drawing is clipped.
- `.exterior()` draws an open area with no walls.

### Wireframe objects

`Scripts/Facility/WireframeModels.gd` holds simple wireframe models drawn with
an oblique projection so they read as 3D (van, guard_booth, reception, lockers,
carts, decon_shower, charging_rack, plinth, coolant_valve, nanofab,
breaker_panel, console, interface_rig).

- Props: pass a model as the last argument, and it's drawn fitted to the prop
  rect: `.prop(0.2, 1.6, 3.3, 4.6, "", &"van")`. Without a model a prop is a flat
  floor marking.
- Signals: hardware is drawn under the signal icon. Set it explicitly with
  `spawn(...).model(&"nanofab")`, or let it be inferred from the id prefix
  (`coolant_vent_*`, `nano_fabricator_*`, `breaker_panel_*`, terminals; see
  `SIGNAL_MODEL_BY_PREFIX`). Disabled signals draw dimmed.
- A model is a footprint plus parts: `_box`, `_cyl`, `_ring`, `_seg`, with x/y
  normalized to the footprint and heights in pixels.

### Escalation

`RunDefinition.is_escalation_enabled()` (default true). The tutorial returns
false: heat still builds, but thresholds don't spawn escalation signals or
raise difficulty.

`Scripts/Facility/facility_map_layer.gd` draws the map;
`Scripts/Facility/feed_switch_overlay.gd` does the cut.

## Checking whether a route is actually under threat

Encounter exposure was checked with a headless script that walks the runner
through the run many times (with a random hold at the corridor entry, like the
tutorial dialogue) and records how often and how long each signal has the runner
in view. Patrol and sweep phase depends on when a signal comes on screen, so
single walkthroughs are noisy; hit rate over several trials is the useful
number. Section-based clocks would make this deterministic.

## Tutorial port notes

- Feed 1: yard approach (runner swings in from behind the van) and security
  hall; at the end of the hall the route turns down a service stair (the corner).
- Feed 2: everything from the service corridor on. In the corridor the runner
  hugs the top wall past cam_04, which takes it out of cam_04's reach (it was
  catching the runner every pass on a straight line; now it never does).
- Decorative side rooms: admin wing, vent access, janitorial, security office.
- Floorplan: perimeter → security hall → service corridor → lab access →
  cleanroom → exit hall → drone bay → extraction.
- With lanes further apart, side lanes sit further from the path. Vertical
  patrollers were set to 0.25 cells/s (0.15 × 90/54) to keep their old crossing
  timing, and some cameras/drones got longer sensor cones. Contact time per
  encounter was compared against the old layout with a scripted runner walk.
- In-game tutorial dialogue docks to the right of the terminal in map mode, since
  targets now sit mid-screen. Cutscene dialogue stays centered.

## Not done yet

- Walls are visual only: no line-of-sight blocking, and patrols don't collide.
- Disruptor/alert range is still horizontal cell distance, not room-aware.
- Branching routes / shortcuts (a section could hold alternative paths).
- Per-section clocks for patrols/sweeps, and a scrub/exposure view.
- Idea: split the lookahead across stacked windows (next 0-15s, 15-30s, 30-45s).
