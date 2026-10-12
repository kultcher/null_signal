extends Node

@export var settings: GauntletSettings

@onready var game = $Game
@onready var recorder: PlaytestRecorder = $Recorder
@onready var delay: Timer = $NextTrial
@onready var fields: Control = $HUD/Settings/Fields
@onready var status: Label = $HUD/Bar/Rows/Status
@onready var buttons: HBoxContainer = $HUD/Bar/Rows/Buttons
@onready var timeline = $Game/SignalTimeline/TimelineManager
@onready var signal_manager = $Game/SignalTimeline/SignalManager

var sampler := GauntletSampler.new()
var current: ActiveSignal
var last_case: Dictionary = {}
var last_trial := 0
var last_outcome := ""
var started := false
var ended := false
var _transitioning := false
var _repeat_requested := false
var _paused_before_settings := false
var _successes := 0
var _breaches := 0
var _sequence := 0
var _current_case: Dictionary = {}
var _current_trial := 0
var _repeat_case: Dictionary = {}
var _repeat_of := 0
var _current_host := "door"
# Active encounter groups: {"group", "inst", "sigs", "end_cell", "case"}.
var encounters: Array[Dictionary] = []
var _last_encounter_case: Dictionary = {}
var _last_spawn_wall := -INF
var _heated := 0

const NUMBER_FIELDS := ["ic_count", "ic_min", "ic_max", "puzzle_min", "puzzle_max", "shuffle_seed", "breach_delay_sec", "next_delay_sec", "runner_speed", "encounter_difficulty", "cadence_sec", "warmup_trials"]
const RATING_KEYS := {KEY_F4: 1, KEY_F5: 2, KEY_F6: 3}

func _enter_tree() -> void:
	$Game/RunManager.level_script_path = "res://Resources/RunData/AuthoredRuns/CalibrationRun.gd"
	$Game/RunManager.debug_free_play = true
	$Game/SignalTimeline.position.y = 112
	$Game/SignalTimeline/TimelineManager.map_height_px = 460
	$Game/WindowManager.game_over_on_runner_death = false
	$Game/LevelViewer.process_mode = Node.PROCESS_MODE_DISABLED

func _ready() -> void:
	if settings == null:
		settings = GauntletSettings.new()
	game.get_node("WindowManager").process_mode = Node.PROCESS_MODE_PAUSABLE
	game.get_node("WindowManager").auto_focus_puzzles = false
	game.get_node("WindowManager").set_process_input(false)
	game.get_node("TempQuitButton").hide()
	GlobalEvents.first_null_spike = false
	CommandDispatch.terminal_window.disruptions.immediate_keys = PackedInt32Array([KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10])
	_build_extra_fields()
	if settings.tester == "tester":
		var last := recorder.load_last_tester()
		if not last.is_empty():
			settings.tester = String(last.get("tester", settings.tester))
			settings.skill_tag = String(last.get("skill", settings.skill_tag))
	_load_fields()
	fields.get_node("Apply").pressed.connect(apply_settings)
	buttons.get_node("Settings").pressed.connect(show_settings)
	buttons.get_node("Pause").pressed.connect(toggle_pause)
	buttons.get_node("Repeat").pressed.connect(repeat_last)
	buttons.get_node("Skip").pressed.connect(skip_trial)
	buttons.get_node("End").pressed.connect(end_session)
	recorder.trial_finished.connect(_trial_finished)
	recorder.encounter_finished.connect(_encounter_finished)
	recorder.storage_failed.connect(func(message: String): $HUD/Bar/Rows/Output.text = message)
	delay.timeout.connect(spawn_next)
	get_tree().paused = true

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if RATING_KEYS.has(event.keycode):
		if started and not ended and recorder.rate_last(RATING_KEYS[event.keycode]):
			last_outcome += "  [rated %s]" % ["easy", "fine", "hard"][RATING_KEYS[event.keycode] - 1]
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_F7: toggle_pause()
		KEY_F8: repeat_last()
		KEY_F9: skip_trial()
		KEY_F10: end_session()
		_: return
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	_update_running_trials()
	var idle := current == null and encounters.is_empty()
	var phase := "SETUP" if not started else ("ENDED" if ended else ("PAUSED" if get_tree().paused else ("NEXT TRIAL" if idle else "ACTIVE")))
	var elapsed := 0.0
	if current != null:
		var trial: Dictionary = recorder.active.get(current.get_instance_id(), {})
		elapsed = recorder.wall_clock - float(trial.get("started", recorder.wall_clock))
	elif not encounters.is_empty():
		var group: Dictionary = recorder.groups.get(encounters[0].group, {})
		elapsed = recorder.wall_clock - float(group.get("started", recorder.wall_clock))
	if settings.trial_source == "encounters":
		status.text = "CALIBRATION // %s    ENCOUNTER %d (%d active)    %.1fs    CLEAN %d / HEATED %d / HIT %d    LAST: %s    RATE F4/F5/F6" % [phase, _sequence, encounters.size(), elapsed, _successes, _heated, _breaches, last_outcome]
	else:
		status.text = "CALIBRATION // %s    TRIAL %d    %.1fs    CLEARED %d / BREACHED %d    LAST: %s    RATE F4/F5/F6" % [phase, _sequence, elapsed, _successes, _breaches, last_outcome]
	buttons.get_node("Pause").disabled = not started or ended
	buttons.get_node("End").disabled = not started or ended
	buttons.get_node("Settings").disabled = ended
	buttons.get_node("Pause").text = "Resume [F7]" if get_tree().paused else "Pause [F7]"
	buttons.get_node("Repeat").disabled = (last_case.is_empty() and current == null and _last_encounter_case.is_empty() and encounters.is_empty()) or ended
	buttons.get_node("Skip").disabled = (current == null and encounters.is_empty()) or ended

# Ends trials that finish by position rather than by an event: a camera host
# is resolved once the runner is past it; an encounter once the runner leaves
# its footprint. Also spawns cadenced encounters.
func _update_running_trials() -> void:
	if not started or ended or get_tree().paused:
		return
	var runner: float = timeline.current_cell_pos
	if current != null and _current_host == "camera" and runner > current.start_cell_index + 0.4:
		var trial: Dictionary = recorder.active.get(current.get_instance_id(), {})
		if not trial.is_empty():
			# Outcome is whether the camera saw the runner; heat alone can come
			# from the camera's IC (Tripwire, Trace) without any detection.
			recorder.finish_trial(current, "detected" if trial.detected else "success", "passed")
	for enc in encounters.duplicate():
		if runner > float(enc.end_cell) + 0.5:
			_finish_encounter(enc, "")
	if settings.trial_source == "encounters" and settings.cadence_sec > 0.0 and not encounters.is_empty() \
			and encounters.size() < settings.max_concurrent and recorder.wall_clock - _last_spawn_wall >= settings.cadence_sec:
		_spawn_encounter()

func _load_fields() -> void:
	fields.get_node("Numbers/ic_count").max_value = GauntletSettings.DISRUPTIVE_IC.size() if settings.trial_source == "encounters" else settings.available_ic().size()
	for key in NUMBER_FIELDS:
		fields.get_node("Numbers/" + key).value = settings.get(key)
	fields.get_node("EncounterRow/Source").select(1 if settings.trial_source == "encounters" else 0)
	fields.get_node("EncounterRow/Host").select(1 if settings.host == "camera" else 0)
	fields.get_node("Leads").text = GauntletSettings.format_leads(settings.lead_cells)
	fields.get_node("EncounterDisruptions").button_pressed = settings.encounter_disruptions
	for key in GauntletSettings.CAMERA_IC:
		fields.get_node("Pools/IC/" + key).button_pressed = key in settings.ic_pool
	for key in GauntletSettings.ENCOUNTERS:
		fields.get_node("Pools/Encounters/" + key).button_pressed = key in settings.encounter_pool
	fields.get_node("Tester").text = settings.tester
	fields.get_node("Skill").text = settings.skill_tag
	fields.get_node("Mode").select(0 if settings.isolated_elements else 1)
	fields.get_node("Puzzle").button_pressed = settings.puzzle_enabled
	fields.get_node("Baseline").button_pressed = settings.include_baseline
	fields.get_node("ResetHeat").button_pressed = settings.reset_heat_each_trial
	for key in GauntletSettings.DOOR_IC:
		fields.get_node("Pools/IC/" + key).button_pressed = key in settings.ic_pool
	for key in GauntletSettings.PUZZLES:
		fields.get_node("Pools/Puzzles/" + key).button_pressed = key in settings.puzzle_pool
	_refresh_ic_controls()

func apply_settings() -> void:
	for key in NUMBER_FIELDS:
		settings.set(key, fields.get_node("Numbers/" + key).value)
	settings.trial_source = "encounters" if fields.get_node("EncounterRow/Source").selected == 1 else "elements"
	settings.host = "camera" if fields.get_node("EncounterRow/Host").selected == 1 else "door"
	settings.lead_cells = GauntletSettings.parse_leads(fields.get_node("Leads").text)
	settings.encounter_disruptions = fields.get_node("EncounterDisruptions").button_pressed
	settings.tester = fields.get_node("Tester").text.strip_edges()
	settings.skill_tag = fields.get_node("Skill").text.strip_edges()
	settings.isolated_elements = fields.get_node("Mode").selected == 0
	settings.puzzle_enabled = fields.get_node("Puzzle").button_pressed
	settings.include_baseline = fields.get_node("Baseline").button_pressed
	settings.reset_heat_each_trial = fields.get_node("ResetHeat").button_pressed
	settings.ic_pool.clear()
	settings.puzzle_pool.clear()
	for key in GauntletSettings.DOOR_IC + GauntletSettings.CAMERA_IC:
		if fields.get_node("Pools/IC/" + key).button_pressed:
			settings.ic_pool.append(key)
	settings.encounter_pool.clear()
	for key in GauntletSettings.ENCOUNTERS:
		if fields.get_node("Pools/Encounters/" + key).button_pressed:
			settings.encounter_pool.append(key)
	for key in GauntletSettings.PUZZLES:
		if fields.get_node("Pools/Puzzles/" + key).button_pressed:
			settings.puzzle_pool.append(key)
	settings = settings.normalized_copy()
	_load_fields()
	sampler.configure(settings)
	if not started:
		if not recorder.start_session(settings.tester, settings.skill_tag, PlaytestRecorder.resource_values(settings)):
			return
		started = true
		$HUD/Settings.hide()
		fields.get_node("Tester").editable = false
		fields.get_node("Skill").editable = false
		$HUD/Bar/Rows/Output.text = "OUTPUT // " + ProjectSettings.globalize_path(recorder.output_path)
		get_tree().paused = false
		spawn_next()
	else:
		$HUD/Settings.hide()
		recorder.write_event("settings_changed", null, {"settings": PlaytestRecorder.resource_values(settings), "coverage": "sampled" if sampler.sampled_combinations else "shuffled_matrix"})
		get_tree().paused = _paused_before_settings

func show_settings() -> void:
	if ended:
		return
	_paused_before_settings = get_tree().paused
	get_tree().paused = true
	$HUD/Settings.show()

func toggle_pause() -> void:
	if not started or ended or $HUD/Settings.visible:
		return
	get_tree().paused = not get_tree().paused

func spawn_next() -> void:
	if ended or not started:
		return
	if settings.trial_source == "encounters":
		_spawn_encounter()
		return
	if current != null:
		return
	_transitioning = false
	var case := _repeat_case.duplicate(true) if _repeat_requested and not _repeat_case.has("template") else sampler.next_case()
	var repeat_of := _repeat_of if _repeat_requested else 0
	_repeat_requested = false
	_sequence += 1
	_reset_corridor()
	var definition: RunDefinition = game.get_node("RunManager").current_run
	_current_host = settings.host
	var data: SignalData
	if _current_host == "camera":
		# Stationary camera on the route (tutorial cam_07): certain watcher.
		data = definition.BASIC_CAMERA.duplicate(true) as SignalData
		data.lane = 2
		data.facing_deg = 0.0
		data.detection.vision_angle_deg = 20.0
		data.detection.vision_length_cells = 1.0
	else:
		data = definition.BASIC_DOOR.duplicate(true) as SignalData
		data.detection.delay = settings.breach_delay_sec
	data.set_meta("auto_codex_popups", false)
	data.system_id = "trial_%04d" % _sequence
	data.display_name = data.system_id
	data.puzzle = null
	data.ic_modules = ICComponent.new()
	if case.puzzle != "none":
		data.puzzle = definition.make_fuzz_puzzle(case.difficulty, settings.fuzz_config) if case.puzzle == "fuzz" else definition.build_puzzle(case.puzzle, case.difficulty)
		data.puzzle.set_custom_fixed()
	for module in case.ic:
		var ic = definition.build_ic(module.ic, module.difficulty)
		ic.set_custom_fixed()
		data.ic_modules.add_module(ic)
	var lead: float = float(case.get("lead", -1.0))
	var runner: float = timeline.current_cell_pos
	var cell: float = runner + lead if lead > 0.0 else timeline.screen_x_to_cell(timeline.screen_width + 80)
	signal_manager.spawn_signal_data(data, cell)
	current = signal_manager.signal_queue[-1]
	var config := PlaytestRecorder.configuration(data)
	config["breach_delay_sec"] = settings.breach_delay_sec
	config["runner_speed"] = settings.runner_speed
	config["shuffle_seed"] = settings.shuffle_seed
	config["coverage"] = "sampled" if sampler.sampled_combinations else "shuffled_matrix"
	config["host"] = _current_host
	config["lead_cells"] = lead
	config["window_sec"] = (cell - runner) / settings.runner_speed
	config["predicted"] = _prediction(data)
	config["warmup"] = _sequence <= settings.warmup_trials
	config["session_index"] = _sequence
	config["exposure"] = recorder.take_exposure(PlaytestRecorder.exposure_keys(config))
	_current_trial = recorder.watch_signal(current, config, repeat_of)
	_current_case = case.duplicate(true)
	signal_manager.update_signal_position()
	CommandDispatch.terminal_window.command_line.grab_focus()

# Rebase the empty corridor between trials; it can run indefinitely without
# hitting the finite fallback route or keeping old signals in memory.
func _reset_corridor() -> void:
	timeline.set_runner_cell(0)
	timeline.clear_speed_mode()
	timeline.BASE_CELLS_PER_SECOND = settings.runner_speed
	timeline.cells_per_second = settings.runner_speed
	if timeline._time_scale_tween != null and timeline._time_scale_tween.is_valid():
		timeline._time_scale_tween.kill()
	timeline.null_spike_active = false
	Engine.time_scale = 1.0
	timeline.get_node("../GridLayer/TimelineBreathEffect").show()
	game.get_node("SignalTimeline/GridLayer/RunnerTeam/PanelContainer/RunnerHealth").reset_health()
	if settings.reset_heat_each_trial:
		game.get_node("HeatManager").set_heat(0, "Trial reset")
		game.get_node("HeatManager").null_spike_count = 0

func _prediction(data: SignalData) -> Dictionary:
	var estimate := CostTable.shared().estimate(data)
	return {"blocking": estimate.blocking, "background": estimate.background, "total": estimate.total, "guesses": estimate.guesses}

# --- encounters ---

func _spawn_encounter() -> void:
	var limit := settings.max_concurrent if settings.cadence_sec > 0.0 else 1
	if encounters.size() >= limit:
		return
	_transitioning = false
	var repeat := _repeat_requested and _repeat_case.has("template")
	var case := _repeat_case.duplicate(true) if repeat else sampler.next_encounter()
	_repeat_requested = false
	_sequence += 1
	if encounters.is_empty():
		_reset_corridor()
	var run: RunDefinition = game.get_node("RunManager").current_run
	var template_id := StringName(case.template)
	var template := EncounterLibrary.make(template_id, settings.encounter_difficulty)
	var runner: float = timeline.current_cell_pos
	var anchor: float = runner + float(case.lead) if float(case.lead) > 0.0 else timeline.screen_x_to_cell(timeline.screen_width + 80)
	for enc in encounters:
		anchor = maxf(anchor, float(enc.end_cell) + 1.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(case.seed)
	var inst := template.generate(run, anchor, rng, "enc%03d_%s" % [_sequence, String(template_id).get_slice("_", 0)])
	var preferred_role: String = {"watched_door": "door", "camera_corridor": "cam_fixed", "drone_patrol": "drone_1", "guard_patrol": "cam_reveal"}.get(String(template_id), "")
	var added_ic: Array = []
	var ic_host_role := ""
	var built: Array = []
	var keys: Array[String] = ["enc." + String(template_id)]
	var predicted := 0.0
	var first_cell := INF
	for spawn in inst.spawns:
		var data := run.build_runtime_signal(spawn)
		data.display_name = data.system_id
		data.set_meta("auto_codex_popups", false)
		var role: String = inst.roles.get(data.system_id, "")
		if role == preferred_role and not case.get("ic", []).is_empty():
			_apply_encounter_disruptions(run, data, case.ic)
			added_ic = PlaytestRecorder.configuration(data).ic.filter(func(module): return module.ic in GauntletSettings.DISRUPTIVE_IC)
			ic_host_role = role
		if data.type == SignalData.Type.DOOR and data.detection != null:
			data.detection.delay = settings.breach_delay_sec
		var config := PlaytestRecorder.configuration(data)
		for key in PlaytestRecorder.exposure_keys(config):
			if not key in keys:
				keys.append(key)
		var prediction := _prediction(data)
		predicted += float(prediction.total)
		first_cell = minf(first_cell, float(spawn.cell_index))
		config.merge({"template": String(template_id), "role": inst.roles.get(data.system_id, ""), "predicted": prediction,
			"runner_speed": settings.runner_speed, "breach_delay_sec": settings.breach_delay_sec,
			"warmup": _sequence <= settings.warmup_trials, "session_index": _sequence}, true)
		built.append({"data": data, "cell": float(spawn.cell_index), "config": config})
	var info := {"template": String(template_id), "wildcard": inst.wildcard, "difficulty": settings.encounter_difficulty,
		"flipped": inst.flipped, "seed": int(case.seed), "anchor_cell": anchor, "end_cell": inst.end_cell,
		"lead_cells": float(case.lead), "window_sec": (first_cell - runner) / settings.runner_speed,
		"predicted_total": predicted, "warmup": _sequence <= settings.warmup_trials, "session_index": _sequence,
		"repeat": repeat, "concurrent": encounters.size(), "exposure": recorder.take_exposure(keys),
		"added_ic": added_ic, "ic_host_role": ic_host_role, "ic_case": case.get("ic", []).duplicate(true)}
	var group := recorder.begin_group(info)
	var sigs: Array[ActiveSignal] = []
	for item in built:
		item.config["encounter"] = group
		signal_manager.spawn_signal_data(item.data, item.cell)
		var sig: ActiveSignal = signal_manager.signal_queue[-1]
		sigs.append(sig)
		recorder.watch_signal(sig, item.config, 0, group)
	encounters.append({"group": group, "inst": inst, "sigs": sigs, "end_cell": inst.end_cell, "case": case})
	_last_spawn_wall = recorder.wall_clock
	signal_manager.update_signal_position()
	CommandDispatch.terminal_window.command_line.grab_focus()

func _finish_encounter(enc: Dictionary, hint: String) -> void:
	if not enc in encounters:
		return
	encounters.erase(enc)
	recorder.end_group(enc.group, hint)
	for sig in enc.sigs:
		_clear_signal(sig)
	if encounters.is_empty() and not ended:
		delay.start(maxf(0.001, settings.next_delay_sec))

func _encounter_finished(summary: Dictionary) -> void:
	var info: Dictionary = summary.info
	_last_encounter_case = {"template": info.template, "seed": info.seed, "lead": info.lead_cells}
	if info.has("ic_case"):
		_last_encounter_case["ic"] = info.ic_case.duplicate(true)
	match summary.outcome:
		"clean": _successes += 1
		"heated": _heated += 1
		"damaged", "breached": _breaches += 1
	var took = summary.visible_to_pass_sec
	last_outcome = "%s (%s, %s)" % [summary.outcome, summary.template, "%.1fs" % took if took != null else "-"]

func _trial_finished(summary: Dictionary) -> void:
	# Encounter members are reported through _encounter_finished.
	if not String(summary.get("group", "")).is_empty():
		return
	last_case = _current_case.duplicate(true)
	last_trial = summary.trial
	if summary.outcome == "success":
		_successes += 1
	elif summary.outcome in ["breached", "detected"]:
		_breaches += 1
	last_outcome = "%s (%s, %.1fs)" % [summary.outcome, summary.case_key, summary.spawn_to_end_sec]
	if _transitioning or ended:
		return
	_transitioning = true
	_cleanup_and_schedule.call_deferred()

func _cleanup_and_schedule() -> void:
	clear_current()
	if not ended:
		delay.start(maxf(0.001, settings.next_delay_sec))

func clear_current() -> void:
	if current == null:
		return
	var sig := current
	current = null
	_clear_signal(sig)

func _clear_signal(sig: ActiveSignal) -> void:
	game.get_node("WindowManager").close_puzzles_for_signal(sig, false)
	game.get_node("WindowManager").clear_focus_overlay()
	game.get_node("SignalTimeline/ScanController").notify_signal_despawned(sig)
	var terminal = CommandDispatch.terminal_window
	if sig.terminal_session != null:
		terminal._close_session_tab(sig.terminal_session, sig)
	sig.release_run_state()
	if sig.instance_node != null and is_instance_valid(sig.instance_node):
		if sig.data.ic_modules != null:
			sig.data.ic_modules.notify_visuals_cleared(sig)
		sig.instance_node.queue_free()
		sig.instance_node = null
	signal_manager.signal_queue.erase(sig)

func repeat_last() -> void:
	if ended:
		return
	if settings.trial_source == "encounters":
		var source: Dictionary = encounters[-1].case if not encounters.is_empty() else _last_encounter_case
		if source.is_empty():
			return
		_repeat_case = source.duplicate(true)
		_repeat_requested = true
		if encounters.is_empty():
			delay.start(maxf(0.001, settings.next_delay_sec))
		for enc in encounters.duplicate():
			_finish_encounter(enc, "repeated")
		return
	if last_case.is_empty() and current == null:
		return
	_repeat_case = last_case.duplicate(true) if not last_case.is_empty() else _current_case.duplicate(true)
	_repeat_of = last_trial if not last_case.is_empty() else _current_trial
	_repeat_requested = true
	if current != null:
		recorder.finish_trial(current, "repeated", "ignored")
	elif not _transitioning:
		delay.start(maxf(0.001, settings.next_delay_sec))

func skip_trial() -> void:
	if ended:
		return
	if current != null:
		recorder.finish_trial(current, "skipped", "ignored")
	for enc in encounters.duplicate():
		_finish_encounter(enc, "skipped")

func end_session() -> void:
	if ended or not started:
		return
	ended = true
	delay.stop()
	for enc in encounters.duplicate():
		_finish_encounter(enc, "interrupted")
	recorder.end_session("complete")
	clear_current()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	$HUD/Settings.hide()
	get_tree().paused = false
	$HUD/Bar/Rows/Output.text = "SAVED // " + ProjectSettings.globalize_path(recorder.output_path) + " (+ CSV)"

func _exit_tree() -> void:
	ended = true
	get_tree().paused = false

# --- extra settings (built in code; the scene stays untouched) ---

func _build_extra_fields() -> void:
	var panel: Control = $HUD/Settings
	panel.offset_top = 112.0
	panel.offset_bottom = 1068.0
	var numbers: GridContainer = fields.get_node("Numbers")
	var spin_template: SpinBox = numbers.get_node("ic_count")
	var label_template: Label = numbers.get_node("Label_ic_count")
	for spec in [["encounter_difficulty", "Enc. difficulty", 1, 5, 1], ["cadence_sec", "Cadence (s)", 0, 120, 0.5], ["warmup_trials", "Warm-up trials", 0, 20, 1]]:
		var label := label_template.duplicate(0) as Label
		label.name = "Label_" + spec[0]
		label.text = spec[1]
		numbers.add_child(label)
		var spin := spin_template.duplicate(0) as SpinBox
		spin.name = spec[0]
		spin.min_value = spec[2]
		spin.max_value = spec[3]
		spin.step = spec[4]
		numbers.add_child(spin)
	var mode: OptionButton = fields.get_node("Mode")
	var row := HBoxContainer.new()
	row.name = "EncounterRow"
	for spec in [["Source", ["Trials: elements (one signal)", "Trials: encounter templates"]], ["Host", ["Element host: door", "Element host: camera (+ Reboot, Heartbeat, Tripwire)"]]]:
		var option := mode.duplicate(0) as OptionButton
		option.name = spec[0]
		option.clear()
		for text in spec[1]:
			option.add_item(text)
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(option)
	fields.add_child(row)
	fields.move_child(row, mode.get_index() + 1)
	row.get_node("Source").item_selected.connect(func(_index): _refresh_ic_controls())
	row.get_node("Host").item_selected.connect(func(_index): _refresh_ic_controls())
	var modifiers := CheckButton.new()
	modifiers.name = "EncounterDisruptions"
	modifiers.text = "Add selected disruptive IC to one encounter host"
	modifiers.toggled.connect(func(_enabled): _refresh_ic_controls())
	fields.add_child(modifiers)
	fields.move_child(modifiers, row.get_index() + 1)
	var leads := fields.get_node("Tester").duplicate(0) as LineEdit
	leads.name = "Leads"
	leads.text = ""
	leads.editable = true
	leads.placeholder_text = "Window sweep: spawn distances in cells, e.g. 3, 5, 7 (blank = screen edge)"
	fields.add_child(leads)
	fields.move_child(leads, numbers.get_index() + 1)
	var ic_grid: GridContainer = fields.get_node("Pools/IC")
	var box_template: CheckBox = ic_grid.get_node("bouncer")
	for key in GauntletSettings.DOOR_IC + GauntletSettings.CAMERA_IC:
		if ic_grid.has_node(key):
			continue
		var box := box_template.duplicate(0) as CheckBox
		box.name = key
		box.text = key.capitalize() + ("*" if key in GauntletSettings.CAMERA_IC else "")
		box.button_pressed = key in settings.ic_pool
		ic_grid.add_child(box)
	var pool := GridContainer.new()
	pool.name = "Encounters"
	pool.columns = 2
	fields.get_node("Pools").add_child(pool)
	for key in GauntletSettings.ENCOUNTERS:
		var box := box_template.duplicate(0) as CheckBox
		box.name = key
		box.text = key.capitalize()
		pool.add_child(box)
	fields.get_node("Note").text = "Single elements uses IC count as off/on; combinations use the exact count. *Camera host only.\nEncounters keep their template puzzles/IC. Optional added disruption uses the six new IC on one host.\nBaseline means no added disruption; cadence > 0 overlaps encounters. Rate the last trial: F4/F5/F6."

func _refresh_ic_controls() -> void:
	var encounters_mode: bool = fields.get_node("EncounterRow/Source").selected == 1
	var camera_host: bool = fields.get_node("EncounterRow/Host").selected == 1
	var available: Array = GauntletSettings.DISRUPTIVE_IC if encounters_mode else (GauntletSettings.DOOR_IC + GauntletSettings.CAMERA_IC if camera_host else GauntletSettings.DOOR_IC)
	fields.get_node("Numbers/ic_count").max_value = available.size()
	fields.get_node("EncounterRow/Host").disabled = encounters_mode
	fields.get_node("EncounterDisruptions").disabled = not encounters_mode
	fields.get_node("Baseline").text = "Include original template (no added disruption)" if encounters_mode else "Include unprotected baseline"
	fields.get_node("Mode").set_item_text(0, "Single additions: original template or one IC" if encounters_mode else "Single elements: baseline, one IC, or one puzzle")
	fields.get_node("Mode").set_item_text(1, "Combined additions: selected IC count" if encounters_mode else "Combinations: selected IC count + optional puzzle")
	fields.get_node("Puzzle").disabled = encounters_mode
	for key in ["puzzle_min", "puzzle_max"]:
		fields.get_node("Numbers/" + key).editable = not encounters_mode
	for key in GauntletSettings.PUZZLES:
		fields.get_node("Pools/Puzzles/" + key).disabled = encounters_mode
	for key in GauntletSettings.DOOR_IC + GauntletSettings.CAMERA_IC:
		fields.get_node("Pools/IC/" + key).disabled = not key in available

func _apply_encounter_disruptions(run: RunDefinition, data: SignalData, requested: Array) -> void:
	if data.ic_modules == null:
		data.ic_modules = ICComponent.new()
	for entry in requested:
		if not entry.ic in GauntletSettings.DISRUPTIVE_IC:
			continue
		# Do not stack duplicate module types if an authored template already
		# contains this IC; the selected profile replaces that instance.
		for index in range(data.ic_modules.modules.size() - 1, -1, -1):
			if PlaytestRecorder.ic_key(data.ic_modules.modules[index]) == entry.ic:
				data.ic_modules.modules.remove_at(index)
		var module := run.build_ic(entry.ic, entry.difficulty) as ICModule
		module.set_custom_fixed()
		data.ic_modules.add_module(module)
