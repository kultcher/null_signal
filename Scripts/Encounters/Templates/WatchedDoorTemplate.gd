# WatchedDoorTemplate.gd
# A puzzle-locked door with a wall camera watching its approach. The door
# stops the runner (a blocker stop point); the camera covers the spot where he
# waits, so a slow solve is paid for in heat. No wildcard. Works as the
# standard transition between sections: place the door on the boundary.
# Tuning follows the tutorial's door_01 / cam_01 pair.
class_name WatchedDoorTemplate extends EncounterTemplate

@export var approach_cells := 3.0           # anchor -> door
@export var exit_cells := 0.5               # door -> end of footprint
@export var puzzle_pool: PackedStringArray = PackedStringArray(["sniff"])
@export var camera_back_cells := 0.4        # camera sits this far before the door
@export var camera_vision_deg := 40.0
@export var camera_reach_margin_cells := 0.4
@export var camera_ic: StringName = &""     # optional IC on the camera

func _init() -> void:
	template_id = &"watched_door"
	display_name = "Watched door"
	tags = PackedStringArray(["transition", "blocker", "watchers"])

func get_base_length() -> float:
	return approach_cells + exit_cells

func get_door_cell(anchor_cell: float) -> float:
	return anchor_cell + approach_cells

func _build(run: RunDefinition, inst: EncounterInstance, rng: RandomNumberGenerator) -> void:
	var door_cell := get_door_cell(inst.anchor_cell)
	var puzzle := String(puzzle_pool[rng.randi_range(0, puzzle_pool.size() - 1)]) if not puzzle_pool.is_empty() else "sniff"
	inst.add("door", run.spawn(RunDefinition.BASIC_DOOR, door_cell)
		.lane(route_lane)
		.add_puzzle(puzzle, difficulty))
	inst.stop_points.append({"cell": door_cell - 0.3, "lane": route_lane, "kind": "blocker"})

	# Wall camera on the outer lane, aimed at the waiting spot before the door.
	var cam := Vector2(door_cell - camera_back_cells, lane_of(inst, 0))
	var target := Vector2(door_cell - 0.4, route_lane)
	var builder := run.spawn(RunDefinition.BASIC_CAMERA, cam.x) \
		.lane(int(cam.y)) \
		.facing(cone_facing_toward(cam, target)) \
		.vision(camera_vision_deg, distance_cells(cam, target) + camera_reach_margin_cells)
	if camera_ic != &"":
		builder.add_ic(camera_ic, difficulty)
	inst.add("cam_watch", builder)
	inst.wildcard = {}
