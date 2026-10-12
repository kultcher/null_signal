extends Node

# Gauntlet expansions: encounter trials (grouped), cadence, window sweep leads,
# camera host, ratings, exposure counts and tester memory.
# Run: godot --headless --fixed-fps 60 res://Tests/gauntlet_encounter_test.tscn

const OUTPUT := "user://gauntlet_encounter_tests"

var failures := 0
var lab

func check(label: String, condition: bool) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures += 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run_checks")

func run_checks() -> void:
	_clear_output()
	# --- settings and sampling ---
	check("lead list parses and drops junk", GauntletSettings.parse_leads("3, x, 5.5,,-1") == PackedFloat32Array([3.0, 5.5]))
	var settings := GauntletSettings.new()
	settings.ic_pool = PackedStringArray(["bouncer", "reboot"])
	settings.puzzle_enabled = false
	settings.lead_cells = PackedFloat32Array([5.0, 3.0, 99.0])
	var normalized := settings.normalized_copy()
	check("door host drops camera-only IC", normalized.ic_pool == PackedStringArray(["bouncer"]))
	check("leads are sorted and clamped to the screen", normalized.lead_cells == PackedFloat32Array([3.0, 5.0, GauntletSettings.MAX_LEAD_CELLS]))
	settings.host = "camera"
	check("camera host keeps camera-only IC", settings.normalized_copy().ic_pool == PackedStringArray(["bouncer", "reboot"]))
	settings.lead_cells = PackedFloat32Array([3.0, 5.0])
	var sampler := GauntletSampler.new()
	sampler.configure(settings)
	check("every case runs at every lead (baseline + 2 IC) x 2 leads", sampler.matrix.size() == 6)
	check("encounter bag covers templates x leads", sampler.encounter_matrix.size() == GauntletSettings.ENCOUNTERS.size() * 2)
	var draw := sampler.next_encounter()
	check("encounter draws carry a seed and lead", draw.has("seed") and draw.lead in [3.0, 5.0])

	lab = load("res://Scenes/Tests/calibration_gauntlet.tscn").instantiate()
	add_child(lab)
	await get_tree().process_frame
	lab.recorder.output_directory = OUTPUT
	check("extra settings fields exist", lab.fields.has_node("EncounterRow/Source") and lab.fields.has_node("Leads") and lab.fields.has_node("Pools/Encounters/guard_patrol") and lab.fields.has_node("Pools/IC/reboot") and lab.fields.has_node("Numbers/cadence_sec"))
	_set_fields({"Tester": "enc tester", "ic_count": 0, "puzzle": false, "leads": "3", "next_delay_sec": 0.05, "breach_delay_sec": 0.2})
	lab.apply_settings()
	await get_tree().process_frame

	# --- element trial at a lead distance ---
	var sig: ActiveSignal = lab.current
	var trial: Dictionary = lab.recorder.active[sig.get_instance_id()]
	check("lead spawns the door 3 cells ahead of the runner", absf(sig.start_cell_index - lab.timeline.current_cell_pos - 3.0) < 0.01)
	check("window, prediction, warm-up and exposure are recorded", is_equal_approx(trial.config.window_sec, 3.0 / lab.settings.runner_speed) and trial.config.predicted.total > 0.0 and trial.config.warmup and trial.config.exposure is Dictionary)
	lab.skip_trial()
	await _frames(2)
	check("rating applies to the last finished trial", lab.recorder.rate_last(3))
	check("nothing left to rate twice", not lab.recorder.rate_last(1))

	# --- camera host: detection heat is attributed by source ---
	_set_fields({"host": 1, "ic_count": 1, "pool_ic": ["reboot"], "leads": ""})
	lab.apply_settings()
	await _next_trial()
	sig = lab.current
	check("camera host spawns a camera with its IC", sig.data.type == SignalData.Type.CAMERA and sig.data.ic_modules.modules.size() == 1)
	_put_runner(sig.start_cell_index - 0.6)
	var heated := await _until(func(): return float(lab.recorder.active.get(sig.get_instance_id(), {}).get("heat", 0.0)) > 0.0, 180)
	check("camera detection heat lands on the camera's trial", heated)
	_put_runner(sig.start_cell_index + 0.6)
	await _until(func(): return lab.current == null, 60)
	check("passing a camera that saw the runner is 'detected'", lab.recorder.records[-1].outcome == "detected" and lab.recorder.records[-1].how == "passed")

	# --- encounter: watched door ---
	_set_fields({"source": 1, "host": 0, "pool_enc": ["watched_door"], "cadence_sec": 0.0})
	lab.apply_settings()
	await _next_trial()
	check("one encounter group spawned", lab.encounters.size() == 1 and lab.recorder.groups.size() == 1)
	var enc: Dictionary = lab.encounters[0]
	check("watched door spawns door + camera", enc.sigs.size() == 2 and lab.signal_manager.signal_queue.size() == 2)
	var door: ActiveSignal = enc.sigs.filter(func(s): return s.data.type == SignalData.Type.DOOR)[0]
	var cam: ActiveSignal = enc.sigs.filter(func(s): return s.data.type == SignalData.Type.CAMERA)[0]
	check("member trials carry template, role and group", lab.recorder.active[door.get_instance_id()].config.role == "door" and lab.recorder.active[cam.get_instance_id()].group == enc.group)
	check("member case keys are kept out of the element baseline", PlaytestRecorder.case_key(lab.recorder.active[cam.get_instance_id()].config).begins_with("enc.watched_door.cam_watch"))
	_put_runner(door.start_cell_index - 0.35)
	var breached := await _until(func(): return not lab.recorder.active.has(door.get_instance_id()), 240)
	check("door breach ends the door's trial", breached and lab.recorder.records[-1].outcome == "breached")
	_put_runner(float(enc.end_cell) + 1.0)
	await _until(func(): return lab.encounters.is_empty(), 60)
	var summary: Dictionary = lab.recorder.encounter_records[-1]
	check("encounter outcome is breached (worse than heated)", summary.outcome == "breached")
	var cam_result: Array = summary.signals.filter(func(r): return r.role == "cam_watch")
	check("camera finished as passed and saw the runner", cam_result.size() == 1 and cam_result[0].outcome == "passed" and cam_result[0].how == "seen" and cam_result[0].heat > 0.0)
	check("encounter heat equals its members' heat", is_equal_approx(summary.heat, summary.signals.reduce(func(a, r): return a + r.heat, 0.0)))
	check("rating applies to the last encounter", lab.recorder.rate_last(2))

	# --- repeat rebuilds the same placement ---
	await _until(func(): return not lab.encounters.is_empty(), 60)
	var first_ids: Array = lab.encounters[0].sigs.map(func(s): return "%s@%.2f" % [s.data.system_id.get_slice("_", 1), s.start_cell_index - lab.encounters[0].inst.anchor_cell])
	var first_seed: int = lab.encounters[0].case.seed
	lab.repeat_last()
	await _until(func(): return not lab.encounters.is_empty() and lab.encounters[0].case.seed == first_seed, 60)
	var again: Array = lab.encounters[0].sigs.map(func(s): return "%s@%.2f" % [s.data.system_id.get_slice("_", 1), s.start_cell_index - lab.encounters[0].inst.anchor_cell])
	check("repeat reuses the seed and rebuilds the same layout", first_ids == again)
	check("the interrupted encounter is recorded as repeated", lab.recorder.encounter_records[-1].outcome == "repeated")

	# --- cadence overlaps encounters ---
	_set_fields({"pool_enc": ["camera_corridor"], "cadence_sec": 0.5})
	lab.apply_settings()
	lab.skip_trial()
	# Cadence runs on the recorder's real-time clock: wait in real time.
	var deadline := Time.get_ticks_msec() + 5000
	while lab.encounters.size() < 2 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check("cadence spawns a second encounter while the first is active", lab.encounters.size() == 2)
	if lab.encounters.size() == 2:
		check("cadenced encounter starts after the first one's footprint", lab.encounters[1].inst.anchor_cell >= float(lab.encounters[0].end_cell) + 1.4)
	lab.skip_trial()
	check("skip ends every active encounter", lab.encounters.is_empty() and lab.recorder.encounter_records[-1].outcome == "skipped")

	# --- files ---
	var path: String = lab.recorder.output_path
	var encounter_csv: String = OUTPUT.path_join(lab.recorder.session + "_encounters.csv")
	lab.end_session()
	var events: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		events.append(JSON.parse_string(line))
	check("encounter start/end and ratings are in the JSONL", events.any(func(e): return e.event == "encounter_started") and events.any(func(e): return e.event == "encounter_ended") and events.filter(func(e): return e.event == "rating").size() == 2)
	check("encounter CSV is written", FileAccess.file_exists(encounter_csv) and FileAccess.get_file_as_string(encounter_csv).split("\n", false).size() >= 4)
	var exposure: Dictionary = lab.recorder.load_exposure("enc tester")
	check("exposure counts persist per tester", int(exposure.get("enc.watched_door", 0)) >= 2 and int(exposure.get("ic.reboot", 0)) == 1)
	check("last tester is remembered", lab.recorder.load_last_tester().get("tester") == "enc tester")
	lab.queue_free()
	await _frames(2)
	print("GAUNTLET ENCOUNTER TEST: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _set_fields(values: Dictionary) -> void:
	var fields: Control = lab.fields
	for key in values:
		var value = values[key]
		match key:
			"Tester": fields.get_node("Tester").text = value
			"puzzle": fields.get_node("Puzzle").button_pressed = value
			"leads": fields.get_node("Leads").text = value
			"source": fields.get_node("EncounterRow/Source").select(value)
			"host": fields.get_node("EncounterRow/Host").select(value)
			"pool_ic":
				for name in GauntletSettings.DOOR_IC + GauntletSettings.CAMERA_IC:
					fields.get_node("Pools/IC/" + name).button_pressed = name in value
			"pool_enc":
				for name in GauntletSettings.ENCOUNTERS:
					fields.get_node("Pools/Encounters/" + name).button_pressed = name in value
			_: fields.get_node("Numbers/" + key).value = value

func _next_trial() -> void:
	lab.skip_trial()
	lab.delay.stop()
	await _frames(2)
	lab.spawn_next()
	await _frames(1)

func _put_runner(cell: float) -> void:
	lab.timeline.set_runner_cell(cell)
	lab.signal_manager.update_signal_position()

func _until(condition: Callable, frames: int) -> bool:
	for i in frames:
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _clear_output() -> void:
	var dir := ProjectSettings.globalize_path(OUTPUT)
	for sub in ["", "testers"]:
		var path := dir.path_join(sub)
		if DirAccess.dir_exists_absolute(path):
			for file in DirAccess.get_files_at(path):
				DirAccess.remove_absolute(path.path_join(file))
