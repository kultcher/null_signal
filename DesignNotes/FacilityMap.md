# Facility Map (map mode)

First pass at replacing the abstract timeline strip with a top-down facility map.

## Model

- The runner still moves along a straight path, and progress is still measured in
  **cells** (`TimelineManager.current_cell_pos`). Time-to-contact, `cell_reached`,
  tutorial triggers and range checks are unchanged.
- **Lanes are now real vertical positions** on the map (`map_lane_spacing_px`, 90px
  vs 54px on the old strip). The runner's path is `path_lane` (2).
- The camera follows the runner exactly like the old scroll: runner 1 cell from the
  left edge, 8 cells across the screen, so the ~47s lookahead window is the same.
- `TimelineManager.map_mode` toggles between the map and the old timeline strip.

## Spatial conversions

All screen placement goes through `TimelineManager`:

- `cell_to_screen_x(cell)`, `lane_to_y(lane_pos)`, `cell_lane_to_screen(cell, lane)`
- `screen_x_to_cell(x)`, `get_runner_screen_pos()`

`FacilityLayout` (`Scripts/Facility/`) holds the rooms and has
`project_to_path(cell, lane)`. Today that returns `cell`; branching routes and
shortcuts through doors should extend `FacilityLayout` rather than leak into callers.

## Authoring rooms

Rooms live in the run definition next to the spawns (`get_rooms()` in
`RunDefinition`). Coordinates are cells (x) and lanes (y); room edges usually sit
half a lane outside the outermost lane used, e.g. `lanes(-0.5, 4.5)`.

```gdscript
func get_rooms() -> Array[FacilityRoom]:
	return [
		room("security_hall", 6.5, 17.0) \
			.label("SECURITY HALL") \
			.lanes(-0.5, 4.5) \
			.opening("top", 12.0, 12.8) \          # gap in a side wall
			.prop(7.6, 9.4, -0.5, 0.35, "RECEPTION") \  # visual-only furniture
			.build(),
	]
```

- Put room boundaries where doors sit on the path; walls automatically leave a
  doorway where the path crosses.
- `.exterior()` draws an open area with no walls.
- Runs without rooms fall back to the lane grid.

`Scripts/Facility/facility_map_layer.gd` draws floors, walls, props, labels and the
runner's path.

## Tutorial port notes

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
- Branching paths / shortcuts.
