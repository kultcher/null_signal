extends Node

const OUTPUT := "user://gauntlet_disruption_tests"
var lab
var terminal
var failures := 0
var commanded: Array = []

func check(label: String, condition: bool) -> void:
	print("GAUNTLET DISRUPTION ", "PASS " if condition else "FAIL ", label)
	if not condition:
		failures += 1

func _ready() -> void:
	_test_sampler()
	lab = load("res://Scenes/Tests/calibration_gauntlet.tscn").instantiate()
	add_child(lab)
	await frames(2)
	lab.recorder.output_directory = OUTPUT
	terminal = CommandDispatch.terminal_window
	CommandDispatch.command_submitted.connect(func(text, sig): commanded.append([text, sig]))
	check("new IC selectors are generated", GauntletSettings.DISRUPTIVE_IC.all(func(key): return lab.fields.has_node("Pools/IC/" + key)))
	check("door count limit grows beyond seven", lab.fields.get_node("Numbers/ic_count").max_value == 13)
	check("expanded setup panel keeps Apply visible", lab.get_node("HUD/Settings").get_global_rect().encloses(lab.fields.get_node("Apply").get_global_rect()))
	for key in GauntletSettings.DISRUPTIVE_IC:
		await element(key)
		var sig: ActiveSignal = lab.current
		check(key + " spawns and records resolved tuning", sig.data.ic_modules.modules.size() == 1 and lab.recorder.active[sig.get_instance_id()].config.ic[0].ic == key and not lab.recorder.active[sig.get_instance_id()].config.ic[0].resolved.uses_escalation_difficulty)
		terminal.switch_session(sig, false)
		await frames(2)
		var trial: Dictionary = lab.recorder.active[sig.get_instance_id()]
		check(key + " effect start is attributed to its trial", trial.disruption_counts.get(key + ".started", 0) == 1)
		if key == "lag":
			var before := commanded.size()
			for character in "OP":
				key_event(character.unicode_at(0), character.unicode_at(0))
			key_event(KEY_ENTER)
			check("Lag queue friction precedes command delivery", commanded.size() == before and trial.disruption_counts.get("lag.queued", 0) == 3)
			key_event(KEY_F7)
			check("F7 remains immediate with Lag input pending", get_tree().paused)
			var age: float = terminal.disruptions.sessions[sig.get_instance_id()].age
			await get_tree().create_timer(0.1, true).timeout
			check("pause freezes disruptions and retains queued input", is_equal_approx(age, terminal.disruptions.sessions[sig.get_instance_id()].age) and commanded.size() == before)
			key_event(KEY_F7)
			check("F7 resumes while terminal still has Lag", not get_tree().paused)
			for i in range(100):
				if lab.current == null:
					break
				await get_tree().physics_frame
			check("delayed OP completes real door trial", lab.recorder.records[-1].outcome == "success" and lab.recorder.records[-1].disruption_counts.get("lag.submitted", 0) == 1)
			await frames(2)
			lab.delay.stop()
		elif key == "spammer":
			# Tier five spawns every .8 game seconds; continue on the root tab.
			terminal.restore_session(terminal.root_session)
			await get_tree().create_timer(0.9).timeout
			var state: Dictionary = terminal.disruptions.sessions[sig.get_instance_id()]
			check("background spam is attributed to host", trial.disruption_counts.get("spammer.spawned", 0) >= 1)
			var popup = state.popups[0]
			popup.get_child(0).get_child(0).get_child(1).pressed.emit()
			check("popup dismissal is recorded", trial.disruption_counts.get("spammer.dismissed", 0) == 1)
		elif key == "glitch":
			var state: Dictionary = terminal.disruptions.sessions[sig.get_instance_id()]
			state.age = sig.data.ic_modules.modules[0].jump_interval_sec + 0.05
			terminal.disruptions._update_signal_visuals()
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			sig.instance_node._on_area_2d_input_event(get_viewport(), click, 0)
			check("fake click friction is recorded", trial.disruption_counts.get("glitch.fake_clicked", 0) == 1)
		if sig.terminal_session != null and sig.terminal_session.has_tab:
			terminal._close_session_tab(sig.terminal_session, sig)
			check(key + " manual disconnect is recorded", trial.disruption_counts.get(key + ".ended", 0) == 1)
		await clear_trial()
	await element("blackout", true)
	check("new IC work on camera hosts", lab.current.data.type == SignalData.Type.CAMERA and lab.settings.ic_pool.has("blackout") and lab.fields.get_node("Numbers/ic_count").max_value == 16)
	terminal.switch_session(lab.current, false)
	await clear_trial()
	check("camera cleanup restores Blackout feed", not terminal.disruptions.is_blacked_out())
	await _test_encounters()
	var log_path: String = lab.recorder.output_path
	var csv_path: String = lab.recorder.csv_path
	lab.end_session()
	var events: Array = []
	for line in FileAccess.get_file_as_string(log_path).split("\n", false):
		events.append(JSON.parse_string(line))
	check("friction JSONL includes host, tier, phase and trial", events.any(func(event): return event.event == "ic_disruption" and event.ic == "glitch" and event.phase == "fake_clicked" and event.difficulty == 5 and event.has("trial") and event.has("signal")))
	check("trial CSV carries structured friction counts", "disruption_counts" in FileAccess.get_file_as_string(csv_path) and "lag.queued" in FileAccess.get_file_as_string(csv_path))
	if "--capture-gauntlet-disruptions" in OS.get_cmdline_user_args():
		lab.fields.get_parent().show()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/gauntlet-disruptions-settings.png")
	lab.queue_free()
	await frames(2)
	print("GAUNTLET DISRUPTION TEST: %d failures" % failures)
	get_tree().quit(1 if failures else 0)

func _test_sampler() -> void:
	var settings := GauntletSettings.new()
	settings.trial_source = "encounters"
	settings.encounter_disruptions = true
	settings.ic_pool = PackedStringArray(["lag", "glitch", "bouncer"])
	settings.ic_min = 2
	settings.ic_max = 3
	settings.encounter_pool = PackedStringArray(["watched_door", "camera_corridor"])
	settings.lead_cells = PackedFloat32Array([2, 4])
	settings.puzzle_enabled = true
	var first := GauntletSampler.new()
	var second := GauntletSampler.new()
	first.configure(settings)
	second.configure(settings)
	check("encounter matrix crosses templates, leads and IC tiers", first.encounter_matrix.size() == 20)
	check("encounter variants include authored baseline and only disruptive additions", first.encounter_matrix.any(func(case): return case.ic.is_empty()) and first.encounter_matrix.all(func(case): return case.ic.size() <= 1 and case.ic.all(func(entry): return entry.ic in ["lag", "glitch"])))
	var one: Array = []
	var two: Array = []
	for i in 20:
		one.append(first.next_encounter())
		two.append(second.next_encounter())
	check("seed reproduces added IC and encounter sequence", one == two)
	settings.isolated_elements = false
	settings.ic_count = 2
	settings.ic_min = 1
	settings.ic_max = 1
	settings.include_baseline = false
	first.configure(settings)
	check("combination encounter variants have exact distinct IC count", first.encounter_matrix.size() == 4 and first.encounter_matrix.all(func(case): return case.ic.size() == 2))
	settings.encounter_disruptions = false
	first.configure(settings)
	check("default encounters retain authored templates", first.encounter_matrix.size() == 4 and first.encounter_matrix.all(func(case): return not case.has("ic")))

func _test_encounters() -> void:
	for template in GauntletSettings.ENCOUNTERS:
		lab.fields.get_node("EncounterRow/Source").select(1)
		lab.fields.get_node("EncounterDisruptions").button_pressed = true
		lab._refresh_ic_controls()
		for key in GauntletSettings.DOOR_IC + GauntletSettings.CAMERA_IC:
			lab.fields.get_node("Pools/IC/" + key).button_pressed = key in GauntletSettings.DISRUPTIVE_IC
		for key in GauntletSettings.ENCOUNTERS:
			lab.fields.get_node("Pools/Encounters/" + key).button_pressed = key == template
		lab.fields.get_node("Mode").select(1)
		lab.fields.get_node("Numbers/ic_count").value = 6
		lab.fields.get_node("Numbers/encounter_difficulty").value = 2
		lab.apply_settings()
		lab.spawn_next()
		await frames(2)
		var enc: Dictionary = lab.encounters[0]
		var hosts: Array = enc.sigs.filter(func(sig): return sig.data.ic_modules != null and sig.data.ic_modules.modules.any(func(module): return module is DisruptionModule))
		check(template + " adds selected IC to exactly one host", hosts.size() == 1 and hosts[0].data.ic_modules.modules.filter(func(module): return module is DisruptionModule).size() == 6)
		var sig: ActiveSignal = hosts[0]
		var info: Dictionary = lab.recorder.groups[enc.group].info
		check(template + " records added IC, resolved knobs and host role", info.added_ic.size() == 6 and not info.ic_host_role.is_empty() and info.added_ic[0].resolved.has("delay_sec"))
		if template == "watched_door":
			check("added IC retains authored door puzzle", sig.data.puzzle != null)
		elif template == "camera_corridor":
			check("added IC retains authored camera Bouncer", sig.data.ic_modules.modules.any(func(module): return module is BouncerModule))
		lab.timeline.set_runner_cell(sig.start_cell_index - 0.2)
		lab.signal_manager.update_signal_position()
		terminal.switch_session(sig, false)
		await frames(2)
		check(template + " Blackout acts through the encounter session", terminal.disruptions.is_blacked_out())
		lab._finish_encounter(enc, "skipped")
		lab.delay.stop()
		await frames(2)
		var summary: Dictionary = lab.recorder.encounter_records[-1]
		check(template + " aggregates friction and clears host effects", summary.disruption_counts.get("blackout.started", 0) == 1 and not terminal.disruptions.is_blacked_out() and terminal.disruptions.sessions.is_empty())
		if template == "watched_door":
			lab.repeat_last()
			lab.delay.stop()
			lab.spawn_next()
			await frames(2)
			var repeated: Dictionary = lab.encounters[0]
			check("repeat retains added IC and template seed", repeated.case.ic == enc.case.ic and repeated.case.seed == enc.case.seed and repeated.sigs[0].data.ic_modules != enc.sigs[0].data.ic_modules)
			lab._finish_encounter(repeated, "skipped")
			lab.delay.stop()
			await frames(2)

func element(key: String, camera := false) -> void:
	lab.fields.get_node("EncounterRow/Source").select(0)
	lab.fields.get_node("EncounterRow/Host").select(1 if camera else 0)
	lab.fields.get_node("EncounterDisruptions").button_pressed = false
	lab._refresh_ic_controls()
	lab.fields.get_node("Mode").select(0)
	lab.fields.get_node("Tester").text = "disruption integration"
	lab.fields.get_node("Numbers/warmup_trials").value = 0
	lab.fields.get_node("Numbers/next_delay_sec").value = 30
	lab.fields.get_node("Numbers/runner_speed").value = 0.01
	lab.fields.get_node("Numbers/ic_count").value = 1
	lab.fields.get_node("Numbers/ic_min").value = 5
	lab.fields.get_node("Numbers/ic_max").value = 5
	lab.fields.get_node("Leads").text = "2"
	lab.fields.get_node("Puzzle").button_pressed = false
	lab.fields.get_node("Baseline").button_pressed = false
	for name in GauntletSettings.DOOR_IC + GauntletSettings.CAMERA_IC:
		lab.fields.get_node("Pools/IC/" + name).button_pressed = name == key
	lab.apply_settings()
	if lab.current == null:
		lab.spawn_next()
	await frames(2)

func clear_trial() -> void:
	if lab.current != null:
		lab.skip_trial()
	await frames(2)
	lab.delay.stop()

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func key_event(code: int, unicode_value := 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = unicode_value
	event.pressed = true
	get_viewport().push_input(event, true)
