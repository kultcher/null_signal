# DronePatrolTemplate.gd
# Two drones on staggered vertical patrols across the route: the runner slips
# between their crossings. Wildcard: a third drone on either a long horizontal
# patrol beside the route or a small square patrol over it, placed before or
# after the pair. Tuning follows the tutorial's c_drone_02/03 (vertical),
# drone_02 (horizontal) and drone_01 (square).
class_name DronePatrolTemplate extends EncounterTemplate

@export var lead_cells := 1.5
@export var pair_spacing_cells := 2.0
@export var tail_cells := 1.5
@export var vertical_speed := 0.25
@export var vertical_dwell_sec := 3.0
@export var vertical_vision_deg := 60.0
@export var vertical_length_cells := 0.8
@export var drone_ic: StringName = &""
@export var wildcard_enabled := true
@export var wildcard_gap_cells := 2.0
@export var horizontal_span_cells := 6.0
@export var horizontal_dwell_sec := 3.0
@export var square_size_cells := 1.0
@export var square_speed := 0.2
@export var square_dwell_sec := 1.0

func _init() -> void:
	template_id = &"drone_patrol"
	display_name = "Drone patrol"
	tags = PackedStringArray(["patrol", "timing"])

func get_base_length() -> float:
	return lead_cells + pair_spacing_cells + tail_cells

func get_max_length() -> float:
	return get_base_length() + (wildcard_gap_cells + horizontal_span_cells if wildcard_enabled else 0.0)

func _build(run: RunDefinition, inst: EncounterInstance, rng: RandomNumberGenerator) -> void:
	var wild := wildcard_enabled and inst.wildcard_active
	var pattern := "horizontal" if rng.randf() < 0.5 else "square"
	var position := "lead" if rng.randf() < 0.5 else "tail"
	var wild_span := 0.0
	if wild:
		wild_span = horizontal_span_cells if pattern == "horizontal" else square_size_cells
	var pair_start := inst.anchor_cell + lead_cells
	if wild and position == "lead":
		pair_start += wild_span + wildcard_gap_cells

	# The pair: tutorial c_drone_02 (lanes 0-3) and c_drone_03 (lanes 1-4),
	# two cells apart. Mirroring swaps which one hugs the top.
	for i in 2:
		var cell := pair_start + i * pair_spacing_cells
		var lane := lane_of(inst, 1 + i)
		var points := patrol_points(inst, [[0.0, -1.0, vertical_dwell_sec, 0.0], [0.0, 2.0, vertical_dwell_sec, 0.0]])
		var builder := run.spawn(RunDefinition.BASIC_DRONE, cell) \
			.lane(lane) \
			.move_speed(vertical_speed) \
			.vision(vertical_vision_deg, vertical_length_cells)
		apply_patrol(builder, points)
		if drone_ic != &"":
			builder.add_ic(drone_ic, difficulty)
		inst.add("drone_%d" % (i + 1), builder)
	var pair_end := pair_start + pair_spacing_cells
	inst.end_cell = pair_end + tail_cells

	if not wild:
		return
	var wild_cell := inst.anchor_cell + lead_cells if position == "lead" else pair_end + wildcard_gap_cells
	var builder: RunDefinition.SpawnBuilder
	if pattern == "horizontal":
		# Beside the route, one lane off, sweeping its cone across it.
		var lane := lane_of(inst, 1) if rng.randf() < 0.5 else lane_of(inst, 3)
		builder = run.spawn(RunDefinition.BASIC_DRONE, wild_cell).lane(lane)
		apply_patrol(builder, patrol_points(inst, [[0.0, 0.0, horizontal_dwell_sec, 0.0], [horizontal_span_cells, 0.0, horizontal_dwell_sec, 0.0]]))
		inst.wildcard = {"kind": "drone", "pattern": pattern, "position": position, "lane": lane}
	else:
		# Square over the route: lanes 1-3, square_size cells wide.
		var lane := lane_of(inst, 3)
		builder = run.spawn(RunDefinition.BASIC_DRONE, wild_cell).lane(lane).move_speed(square_speed)
		var points := patrol_points(inst, [
			[0.0, -2.0, square_dwell_sec, 0.0], [square_size_cells, -2.0, square_dwell_sec, 0.0],
			[square_size_cells, 0.0, square_dwell_sec, 0.0], [0.0, 0.0, square_dwell_sec, 0.0]])
		apply_patrol(builder, points)
		inst.wildcard = {"kind": "drone", "pattern": pattern, "position": position, "lane": lane}
	if drone_ic != &"":
		builder.add_ic(drone_ic, difficulty)
	inst.add("drone_wild", builder)
	if position == "tail":
		inst.end_cell = maxf(inst.end_cell, wild_cell + wild_span + tail_cells)
