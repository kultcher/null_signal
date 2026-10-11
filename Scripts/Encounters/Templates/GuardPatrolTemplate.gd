# GuardPatrolTemplate.gd
# Two guards on dodgeable patrols (a square loop and an L that ping-pongs),
# both kept inside the guard-reveal range of one camera, plus a disruptor to
# pull one of them away. Guards stay hidden unless the runner is close or the
# player holds a session on that camera, so the camera is the key to reading
# the room. The camera itself looks along the wall, not at the route.
# No wildcard. Tuning follows Night Audit's 14F guards and printer.
class_name GuardPatrolTemplate extends EncounterTemplate

@export var lead_cells := 1.0
@export var guard_gap_cells := 3.5          # guard A spawn -> guard B spawn
@export var shape_width_cells := 2.0
@export var tail_cells := 1.0
@export var guard_speed := 0.15
@export var guard_dwell_sec := 2.0
@export var camera_vision_deg := 30.0
@export var camera_length_cells := 1.0
@export var camera_ic: StringName = &""
# Must stay within MobilityComponent.reveal_range_from_camera_cells (3.5).
@export var reveal_range_cells := 3.5

func _init() -> void:
	template_id = &"guard_patrol"
	display_name = "Guard patrol"
	tags = PackedStringArray(["patrol", "reveal", "distraction"])

func get_base_length() -> float:
	return lead_cells + guard_gap_cells + shape_width_cells + tail_cells

func _build(run: RunDefinition, inst: EncounterInstance, rng: RandomNumberGenerator) -> void:
	var a_cell := inst.anchor_cell + lead_cells
	var b_cell := a_cell + guard_gap_cells
	var square_first := rng.randf() < 0.5
	var cells := [a_cell, b_cell]
	var shapes := ["square", "l"] if square_first else ["l", "square"]
	for i in 2:
		var builder: RunDefinition.SpawnBuilder
		var w := shape_width_cells
		var d := guard_dwell_sec
		if shapes[i] == "square":
			# Loop over lanes 1-3: crosses the route on its vertical legs only.
			builder = run.spawn(RunDefinition.BASIC_GUARD, cells[i]).lane(lane_of(inst, 1)).move_speed(guard_speed)
			apply_patrol(builder, patrol_points(inst, [[0.0, 0.0, d, 0.0], [w, 0.0, d, 0.0], [w, 2.0, d, 0.0], [0.0, 2.0, d, 0.0]]))
		else:
			# L: down across the route, then along the far wall; ping-pong.
			builder = run.spawn(RunDefinition.BASIC_GUARD, cells[i]).lane(lane_of(inst, 0)).move_speed(guard_speed) \
				.patrol_mode(MobilityComponent.PatrolMode.PING_PONG)
			apply_patrol(builder, patrol_points(inst, [[0.0, 0.0, d, 0.0], [0.0, 4.0, d, 0.0], [w, 4.0, d, 0.0]]))
		inst.add("guard_%d" % (i + 1), builder)

	# Reveal camera midway between the guards' extents, on the wall the L
	# guard doesn't walk along, looking along that wall (never at the route).
	var west := a_cell
	var east := b_cell + shape_width_cells
	var cam_cell := (west + east) * 0.5
	var cam := run.spawn(RunDefinition.BASIC_CAMERA, cam_cell).lane(lane_of(inst, 0)) \
		.facing(cone_facing(inst, -10.0)) \
		.vision(camera_vision_deg, camera_length_cells)
	if camera_ic != &"":
		cam.add_ic(camera_ic, difficulty)
	inst.add("cam_reveal", cam)

	# Disruptor (1-cell range) at the middle of one guard's patrol, on the far
	# wall, so OP pulls that guard off the route.
	var lured := rng.randi_range(0, 1)
	var lure_cell: float = cells[lured] + shape_width_cells * 0.5
	inst.add("vent", run.spawn(RunDefinition.BASIC_DISRUPTOR, lure_cell).lane(lane_of(inst, 4)))
	inst.end_cell = east + tail_cells
	inst.wildcard = {}
