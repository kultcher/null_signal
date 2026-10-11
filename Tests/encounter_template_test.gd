extends Node

# Encounter templates: generation, fit, wildcards, determinism and threat
# profile (via ReachAnalyzer). Run as a scene:
#   godot --headless res://Tests/encounter_template_test.tscn

const GALLERY := "res://Resources/RunData/AuthoredRuns/EncounterGalleryRun.gd"
const SEEDS := 12
const EXPECTED_COUNTS := {&"watched_door": 2, &"camera_corridor": 5, &"drone_patrol": 3, &"guard_patrol": 4}

var failures := 0

func _ready() -> void:
	var corridor_slots := {}
	var drone_patterns := {}
	var drone_positions := {}
	var flips := {}
	for seed in range(1, SEEDS + 1):
		var built := _build_gallery(seed)
		var run: RunDefinition = built["run"]
		var layout: FacilityLayout = built["layout"]
		var reports: Dictionary = built["reports"]
		var ids := {}
		for spawn in run.get_spawns():
			check("seed %d unique id %s" % [seed, spawn["system_id"]], not ids.has(spawn["system_id"]))
			ids[spawn["system_id"]] = true
		for section in layout.sections:
			check("seed %d section %s defaults to hot entry" % [seed, section.id], section.entry == &"hot")
		for inst in run.instances:
			var tag := "seed %d %s" % [seed, inst.prefix]
			var template := EncounterLibrary.make(inst.template_id)
			check("%s fits the layout %s" % [tag, str(template.check_fit(layout, inst.anchor_cell, inst.get_length()))], template.check_fit(layout, inst.anchor_cell, inst.get_length()).is_empty())
			check("%s spawn count" % tag, inst.spawns.size() == EXPECTED_COUNTS[inst.template_id])
			flips[inst.flipped] = true
			match inst.template_id:
				&"watched_door": _check_watched_door(tag, inst, reports)
				&"camera_corridor":
					corridor_slots[inst.wildcard["slot"]] = true
					_check_corridor(tag, inst, reports)
				&"drone_patrol":
					drone_patterns[inst.wildcard["pattern"]] = true
					drone_positions[inst.wildcard["position"]] = true
					_check_drones(tag, inst, reports)
				&"guard_patrol": _check_guards(tag, inst, reports, built["entries"])
	check("corridor wildcard lands in at least 3 different slots", corridor_slots.size() >= 3)
	check("drone wildcard rolls both patterns", drone_patterns.size() == 2)
	check("drone wildcard rolls both positions", drone_positions.size() == 2)
	check("placements are mirrored both ways", flips.size() == 2)

	var a := _build_gallery(7)
	var b := _build_gallery(7)
	check("same seed reproduces the same spawns", _signature(a["run"]) == _signature(b["run"]))
	check("different seeds differ", _signature(a["run"]) != _signature(_build_gallery(8)["run"]))

	# Cone patrollers face their direction of travel; arcs already did.
	var cone := DetectionComponent.new()
	cone.shape_type = DetectionComponent.ShapeType.CONE
	var arc := DetectionComponent.new()
	arc.shape_type = DetectionComponent.ShapeType.ARC
	check("cone moving right faces 180 (looks right)", is_equal_approx(absf(cone.facing_for_direction(0.0)), 180.0))
	check("arc moving right faces 0", is_equal_approx(arc.facing_for_direction(0.0), 0.0))

	# A template rejects a layout that can't host it.
	var narrow := FacilityLayout.new([_room("narrow", 0.0, 20.0, 1.0, 3.0)], [])
	check("corridor rejects a hall without outer lanes", not CameraCorridorTemplate.new().check_fit(narrow, 1.0).is_empty())

	print("ENCOUNTER TEST: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures > 0 else 0)

func _check_watched_door(tag: String, inst: EncounterInstance, reports: Dictionary) -> void:
	var door: Dictionary = reports[inst.ids_with_role("door")[0]]
	var cam: Dictionary = reports[inst.ids_with_role("cam_watch")[0]]
	check("%s door is a certain blocker" % tag, door["kind"] == "blocker" and door["reach"] == "certain")
	check("%s camera is certain" % tag, cam["reach"] == "certain")
	var stop: float = inst.stop_points[0]["cell"]
	var covers_stop := false
	for interval in cam["intervals"]:
		covers_stop = covers_stop or (stop >= interval["from_cell"] - 0.1 and stop <= interval["to_cell"] + 0.1)
	check("%s camera watches the waiting spot (%.2f)" % [tag, stop], covers_stop)

func _check_corridor(tag: String, inst: EncounterInstance, reports: Dictionary) -> void:
	var fixed: Dictionary = reports[inst.ids_with_role("cam_fixed")[0]]
	check("%s stationary wildcard watches the whole path (certain)" % tag, fixed["reach"] == "certain")
	var pans := inst.ids_with_role("cam_pan")
	check("%s has four panning cameras" % tag, pans.size() == 4)
	for id in pans:
		var r: Dictionary = reports[id]
		check("%s %s sweeps the route (possible, graze < 3s)" % [tag, id], r["reach"] == "possible" and r["exposure_walk"] < 3.0)

func _check_drones(tag: String, inst: EncounterInstance, reports: Dictionary) -> void:
	for id in inst.roles:
		check("%s %s threatens with timing (possible)" % [tag, id], reports[id]["reach"] == "possible")

func _check_guards(tag: String, inst: EncounterInstance, reports: Dictionary, entries: Array) -> void:
	var cam_id := inst.ids_with_role("cam_reveal")[0]
	check("%s reveal camera never watches the route" % tag, reports[cam_id]["reach"] == "never")
	var cam_cell := 0.0
	for entry in entries:
		if entry["data"].system_id == cam_id:
			cam_cell = entry["cell"]
	for id in inst.ids_with_role("guard"):
		var r: Dictionary = reports[id]
		check("%s %s is dodgeable (possible, walk %d%%)" % [tag, id, int(r["hit_walk"] * 100.0)], r["reach"] == "possible" and r["hit_walk"] < 0.6)
		for entry in entries:
			if entry["data"].system_id != id:
				continue
			var within := true
			for point in entry["data"].mobility.patrol_points:
				within = within and absf(point.cell_x - cam_cell) <= entry["data"].mobility.reveal_range_from_camera_cells
			check("%s %s patrols inside the camera's reveal range" % [tag, id], within)

func _build_gallery(seed: int) -> Dictionary:
	OS.set_environment("NULL_ENCOUNTER_SEED", str(seed))
	var run: RunDefinition = load(GALLERY).new()
	var layout := run.build_facility_layout()
	layout.set_lane_to_cell_scale(ReachAnalyzer.LANE_PX / ReachAnalyzer.CELL_PX)
	var entries: Array = []
	for spawn in run.get_spawns():
		entries.append({"data": run.build_runtime_signal(spawn), "cell": float(spawn["cell_index"])})
	return {"run": run, "layout": layout, "entries": entries, "reports": ReachAnalyzer.analyze(layout, entries)}

func _signature(run: RunDefinition) -> String:
	var parts: Array[String] = []
	for spawn in run.get_spawns():
		parts.append("%s@%.2f" % [spawn["system_id"], spawn["cell_index"]])
	return ",".join(parts)

func _room(id: String, start: float, end: float, top: float, bottom: float) -> FacilityRoom:
	var r := FacilityRoom.new()
	r.id = id
	r.start_cell = start
	r.end_cell = end
	r.lane_top = top
	r.lane_bottom = bottom
	return r

func check(name: String, ok: bool) -> void:
	if not ok:
		failures += 1
		print("FAIL " + name)
