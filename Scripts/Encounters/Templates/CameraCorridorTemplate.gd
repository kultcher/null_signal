# CameraCorridorTemplate.gd
# A long stretch with panning cameras alternating between the outer lanes:
# each one sweeps across the route and can be slipped past with timing.
# Wildcard: one stationary camera on the route (it watches the path all the
# time, so it has to be dealt with), inserted at any point in the sequence.
# Tuning follows the tutorial's cam_03..cam_07 run.
class_name CameraCorridorTemplate extends EncounterTemplate

@export_range(1, 8, 1) var camera_count := 4
@export var spacing_cells := 3.0
@export var lead_cells := 1.5               # anchor -> first element, and last -> end
@export var pan_vision_deg := 20.0
@export var pan_length_cells := 1.2
@export var pan_dwell_sec := 3.5
@export var pan_ic: StringName = &""
@export var wildcard_enabled := true
@export var fixed_vision_deg := 20.0
@export var fixed_length_cells := 1.0
# IC on the stationary camera from this difficulty up (tutorial cam_07: Bouncer).
@export var fixed_ic: StringName = &"bouncer"
@export var fixed_ic_min_difficulty := 2

func _init() -> void:
	template_id = &"camera_corridor"
	display_name = "Camera corridor"
	tags = PackedStringArray(["watchers", "timing"])

func get_base_length() -> float:
	return lead_cells * 2.0 + (camera_count - 1) * spacing_cells

func get_max_length() -> float:
	return get_base_length() + (spacing_cells if wildcard_enabled else 0.0)

func _build(run: RunDefinition, inst: EncounterInstance, rng: RandomNumberGenerator) -> void:
	var slots := camera_count + (1 if wildcard_enabled else 0)
	var wild_slot := rng.randi_range(0, camera_count) if wildcard_enabled else -1
	var pan_index := 0
	for slot in slots:
		var cell := inst.anchor_cell + lead_cells + slot * spacing_cells
		if slot == wild_slot:
			var builder := run.spawn(RunDefinition.BASIC_CAMERA, cell) \
				.lane(route_lane) \
				.facing(0.0) \
				.vision(fixed_vision_deg, fixed_length_cells)
			if fixed_ic != &"" and difficulty >= fixed_ic_min_difficulty:
				builder.add_ic(fixed_ic, difficulty)
			inst.add("cam_fixed", builder)
			continue
		# Alternate outer lanes; the first camera's side flips with the placement.
		var top := (pan_index % 2 == 0) != inst.flipped
		var lane := 0 if top else 4
		# Top cameras sweep left -> down -> right, bottom ones left -> up -> right.
		var start: Array[float] = [-1.0 if top else 1.0, pan_dwell_sec]
		var finish: Array[float] = [180.0, pan_dwell_sec]
		var builder := run.spawn(RunDefinition.PANNING_CAMERA, cell) \
			.lane(lane) \
			.vision(pan_vision_deg, pan_length_cells) \
			.detection_sweep(start, finish)
		if pan_ic != &"":
			builder.add_ic(pan_ic, difficulty)
		pan_index += 1
		inst.add("cam_pan_%d" % pan_index, builder)
	inst.end_cell = inst.anchor_cell + lead_cells * 2.0 + (slots - 1) * spacing_cells
	if wildcard_enabled:
		inst.wildcard = {"kind": "stationary_camera", "slot": wild_slot, "of": slots}
