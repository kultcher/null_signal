extends Node

var failures := 0

func check(label: String, condition: bool) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures += 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run_checks")

func run_checks() -> void:
	var settings := GauntletSettings.new()
	settings.ic_pool = PackedStringArray(["callback", "haze"])
	settings.ic_max = 2
	settings.puzzle_pool = PackedStringArray(["sniff", "fuzz"])
	settings.puzzle_max = 2
	var sampler := GauntletSampler.new()
	var twin := GauntletSampler.new()
	sampler.configure(settings)
	twin.configure(settings)
	var unique := {}
	var deterministic := true
	for i in 9:
		var case := sampler.next_case()
		unique[PlaytestRecorder.case_key(case)] = true
		deterministic = deterministic and case == twin.next_case()
	check("single-element matrix covers every selected tier plus baseline", unique.size() == 9)
	check("seed reproduces shuffled configuration order", deterministic)
	settings.isolated_elements = false
	settings.ic_count = 2
	sampler.configure(settings)
	check("small combination matrix exhaustively covers distinct IC tiers", sampler.matrix.size() == 17 and not sampler.sampled_combinations)
	settings.ic_pool = PackedStringArray(GauntletSettings.DOOR_IC)
	settings.ic_count = 7
	settings.ic_max = 20
	sampler.configure(settings)
	check("large combinations use bounded sampling", sampler.sampled_combinations and sampler.matrix.size() == 513)

	var lab = load("res://Scenes/Tests/calibration_gauntlet.tscn").instantiate()
	add_child(lab)
	await get_tree().process_frame
	if "--capture-gauntlet" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/gauntlet-settings.png")
	lab.recorder.output_directory = "user://gauntlet_tests"
	lab.fields.get_node("Numbers/ic_count").value = 0
	lab.fields.get_node("Puzzle").button_pressed = false
	lab.fields.get_node("Numbers/next_delay_sec").value = 10.0
	lab.fields.get_node("Numbers/breach_delay_sec").value = 0.2
	lab.apply_settings()
	await get_tree().process_frame
	var sig: ActiveSignal = lab.current
	check("gauntlet uses disabled escalation and one fresh door", not lab.game.get_node("RunManager").current_run.is_escalation_enabled() and lab.signal_manager.signal_queue.size() == 1 and sig.data.type == SignalData.Type.DOOR)
	check("new door spawns just beyond screen edge", lab.timeline.cell_to_screen_x(sig.start_cell_index) > lab.timeline.screen_width)
	if "--capture-gauntlet" in OS.get_cmdline_user_args():
		lab.timeline.set_runner_cell(1.5)
		lab.signal_manager.update_signal_position()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/gauntlet-play.png")
	CommandDispatch.process_command("ACCESS " + sig.data.system_id, CommandDispatch.terminal_window.root_signal)
	CommandDispatch.process_command("NONSENSE", sig)
	CommandDispatch.process_command("OP", sig)
	check("successful OP immediately completes trial", lab.recorder.records.size() == 1 and lab.recorder.records[0].outcome == "success" and not sig.data.door_locked)
	check("parser rejection counts as command friction", lab.recorder.records[0].failed_commands == 1)
	await get_tree().process_frame
	await get_tree().process_frame
	check("completion tears down scans, windows, sessions and old signal", lab.current == null and lab.signal_manager.signal_queue.is_empty() and sig.terminal_session == null and not GlobalEvents.has_runner_holds())
	lab.delay.stop()
	lab.repeat_last()
	lab.delay.stop()
	lab.spawn_next()
	sig = lab.current
	check("repeat preserves combination but creates fresh resources", sig.data.system_id == "trial_0002" and lab.recorder.active[sig.get_instance_id()].repeat_of == 1 and sig.data.door_locked)
	lab.timeline.set_runner_cell(sig.start_cell_index)
	lab.signal_manager.update_signal_position()
	for i in 40:
		await get_tree().physics_frame
		if sig.data.response._delay_in_progress.has(sig.get_instance_id()):
			break
	check("runner contact starts the real breach window", sig.data.response._delay_in_progress.has(sig.get_instance_id()))
	lab.toggle_pause()
	var before: float = lab.recorder.wall_clock
	await get_tree().create_timer(0.35, true).timeout
	check("pause freezes recorder and breach response", is_equal_approx(before, lab.recorder.wall_clock) and not sig.is_disabled and lab.recorder.records.size() == 1)
	lab.toggle_pause()
	for i in 120:
		if lab.recorder.records.size() >= 2:
			break
		await get_tree().process_frame
	check("actual breach is a failed trial and continues session", lab.recorder.records.size() >= 2 and lab.recorder.records[1].outcome == "breached")
	if lab.current == null:
		lab.delay.stop()
		lab.spawn_next()
	lab.skip_trial()
	await get_tree().process_frame
	await get_tree().process_frame
	check("skip is retained separately from clear and breach", lab.recorder.records[-1].outcome == "skipped")
	lab.delay.stop()
	# Run a real Callback trial to validate IC identifiers and outcome events.
	lab._repeat_requested = true
	lab._repeat_case = {"ic": [{"ic": "callback", "difficulty": 2}], "puzzle": "none", "difficulty": 0}
	lab.spawn_next()
	sig = lab.current
	CommandDispatch.process_command("ACCESS " + sig.data.system_id, CommandDispatch.terminal_window.root_signal)
	while CommandDispatch.terminal_window._connection_send_locked:
		await get_tree().process_frame
	CommandDispatch.process_command("$wrong", sig)
	var callback: CallbackModule = sig.data.ic_modules.modules[0]
	CommandDispatch.process_command("$" + callback.callback_sequence, sig)
	CommandDispatch.process_command("OP", sig)
	check("Callback acceptance and retry are recorded", lab.recorder.records[-1].outcome == "success" and lab.recorder.records[-1].failed_commands == 1)
	await get_tree().process_frame
	await get_tree().process_frame
	lab.delay.stop()
	# Fuzz configuration and generated target are recorded when its window opens.
	lab._repeat_requested = true
	lab._repeat_case = {"ic": [], "puzzle": "fuzz", "difficulty": 1}
	lab.spawn_next()
	sig = lab.current
	CommandDispatch.process_command("ACCESS " + sig.data.system_id, CommandDispatch.terminal_window.root_signal)
	CommandDispatch.process_command("RUN FUZZ", sig)
	await get_tree().process_frame
	var manager = lab.game.get_node("WindowManager")
	var puzzle: FuzzPuzzle = manager._active_puzzle_windows.keys()[0]
	puzzle.grab_focus()
	puzzle.aim_angle = puzzle.state.sweet_spot_angle
	for i in 5:
		puzzle.fire_packet()
	puzzle._process(0.5)
	CommandDispatch.process_command("OP", sig)
	check("puzzle solve phases feed the same immediate OP success", lab.recorder.records[-1].outcome == "success" and lab.recorder.records[-1].puzzle_attempts == 1)
	await get_tree().process_frame
	await get_tree().process_frame
	lab.delay.stop()
	lab._repeat_requested = true
	lab._repeat_case = {"ic": [{"ic": "haze", "difficulty": 2}], "puzzle": "none", "difficulty": 0}
	lab.spawn_next()
	sig = lab.current
	lab.timeline.set_runner_cell(sig.start_cell_index - 2.0)
	lab.signal_manager.update_signal_position()
	await get_tree().process_frame
	var scan = lab.game.get_node("SignalTimeline/ScanController")
	scan.toggle_scan(sig)
	var scan_deadline := Time.get_ticks_msec() + 10000
	while sig.current_scan_index < sig.scan_layers.size() and Time.get_ticks_msec() < scan_deadline:
		await get_tree().process_frame
	check("real Haze scan reveals all layers and releases RAM", sig.current_scan_index == sig.scan_layers.size() and not sig.is_being_scanned and not get_tree().paused)
	CommandDispatch.process_command("ACCESS " + sig.data.system_id, CommandDispatch.terminal_window.root_signal)
	CommandDispatch.process_command("OP", sig)
	await get_tree().process_frame
	await get_tree().process_frame
	lab.delay.stop()
	lab.settings.next_delay_sec = 0.05
	lab.delay.start(0.05)
	var next_deadline := Time.get_ticks_msec() + 5000
	while lab.current == null and Time.get_ticks_msec() < next_deadline:
		await get_tree().process_frame
	check("completed trials automatically spawn the next fresh door", lab.current != null and lab.current.data.door_locked and lab.signal_manager.signal_queue.size() == 1 and not get_tree().paused)
	lab.settings.next_delay_sec = 10.0
	lab.skip_trial()
	await get_tree().process_frame
	await get_tree().process_frame
	lab.delay.stop()
	lab._repeat_requested = true
	lab._repeat_case = {"ic": [{"ic": "bouncer", "difficulty": 1}], "puzzle": "none", "difficulty": 0}
	lab.spawn_next()
	sig = lab.current
	CommandDispatch.process_command("ACCESS " + sig.data.system_id, CommandDispatch.terminal_window.root_signal)
	while CommandDispatch.terminal_window._connection_send_locked:
		await get_tree().process_frame
	var bouncer: BouncerModule = sig.data.ic_modules.modules[0]
	bouncer._on_disconnect_timer_timeout(sig)
	var disconnect_deadline := Time.get_ticks_msec() + 5000
	while sig.terminal_session.has_tab and Time.get_ticks_msec() < disconnect_deadline:
		await get_tree().process_frame
	check("Bouncer removes its session and records the IC event", not sig.terminal_session.has_tab and lab.recorder.active[sig.get_instance_id()].ic_events == 1)
	var path: String = lab.recorder.output_path
	lab.end_session()
	var events: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		events.append(JSON.parse_string(line))
	var contract := true
	for event in events:
		contract = contract and event.has_all(["t", "wall_t", "session", "run", "event", "runner_progress", "speed_mode"])
	check("every JSONL event follows ThreatAndCost common fields", contract)
	check("logs contain Callback neutralization and Fuzz runtime target", events.any(func(e): return e.event == "ic_neutralized" and e.ic == "callback" and e.difficulty == 2) and events.any(func(e): return e.event == "puzzle_opened" and e.has("target_angle_deg")))
	check("visibility, scan phases and Haze trigger are recorded", events.any(func(e): return e.event == "signal_visible") and events.any(func(e): return e.event == "scan_complete") and events.any(func(e): return e.event == "ic_triggered" and e.ic == "haze"))
	check("Bouncer disconnect retains its cause", events.any(func(e): return e.event == "disconnected" and e.reason == "bouncer"))
	check("CSV and run-ended event are flushed", FileAccess.file_exists(lab.recorder.csv_path) and events[-1].event == "run_ended")
	print("GAUNTLET LOG: " + ProjectSettings.globalize_path(path))
	lab.queue_free()
	await get_tree().process_frame
	print("GAUNTLET TEST: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
