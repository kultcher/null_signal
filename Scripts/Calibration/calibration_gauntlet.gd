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
	_load_fields()
	fields.get_node("Apply").pressed.connect(apply_settings)
	buttons.get_node("Settings").pressed.connect(show_settings)
	buttons.get_node("Pause").pressed.connect(toggle_pause)
	buttons.get_node("Repeat").pressed.connect(repeat_last)
	buttons.get_node("Skip").pressed.connect(skip_trial)
	buttons.get_node("End").pressed.connect(end_session)
	recorder.trial_finished.connect(_trial_finished)
	recorder.storage_failed.connect(func(message: String): $HUD/Bar/Rows/Output.text = message)
	delay.timeout.connect(spawn_next)
	get_tree().paused = true

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F7: toggle_pause()
		KEY_F8: repeat_last()
		KEY_F9: skip_trial()
		KEY_F10: end_session()
		_: return
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	var phase := "SETUP" if not started else ("ENDED" if ended else ("PAUSED" if get_tree().paused else ("NEXT TRIAL" if current == null else "ACTIVE")))
	var elapsed := 0.0
	if current != null:
		var trial: Dictionary = recorder.active.get(current.get_instance_id(), {})
		elapsed = recorder.wall_clock - float(trial.get("started", recorder.wall_clock))
	status.text = "CALIBRATION // %s    TRIAL %d    %.1fs    CLEARED %d / BREACHED %d    LAST: %s" % [phase, _sequence, elapsed, _successes, _breaches, last_outcome]
	buttons.get_node("Pause").disabled = not started or ended
	buttons.get_node("End").disabled = not started or ended
	buttons.get_node("Settings").disabled = ended
	buttons.get_node("Pause").text = "Resume [F7]" if get_tree().paused else "Pause [F7]"
	buttons.get_node("Repeat").disabled = (last_case.is_empty() and current == null) or ended
	buttons.get_node("Skip").disabled = current == null or ended

func _load_fields() -> void:
	for key in ["ic_count", "ic_min", "ic_max", "puzzle_min", "puzzle_max", "shuffle_seed", "breach_delay_sec", "next_delay_sec", "runner_speed"]:
		fields.get_node("Numbers/" + key).value = settings.get(key)
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

func apply_settings() -> void:
	for key in ["ic_count", "ic_min", "ic_max", "puzzle_min", "puzzle_max", "shuffle_seed", "breach_delay_sec", "next_delay_sec", "runner_speed"]:
		settings.set(key, fields.get_node("Numbers/" + key).value)
	settings.tester = fields.get_node("Tester").text.strip_edges()
	settings.skill_tag = fields.get_node("Skill").text.strip_edges()
	settings.isolated_elements = fields.get_node("Mode").selected == 0
	settings.puzzle_enabled = fields.get_node("Puzzle").button_pressed
	settings.include_baseline = fields.get_node("Baseline").button_pressed
	settings.reset_heat_each_trial = fields.get_node("ResetHeat").button_pressed
	settings.ic_pool.clear()
	settings.puzzle_pool.clear()
	for key in GauntletSettings.DOOR_IC:
		if fields.get_node("Pools/IC/" + key).button_pressed:
			settings.ic_pool.append(key)
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
	if ended or not started or current != null:
		return
	_transitioning = false
	var case := _repeat_case.duplicate(true) if _repeat_requested else sampler.next_case()
	var repeat_of := _repeat_of if _repeat_requested else 0
	_repeat_requested = false
	_sequence += 1
	# Rebase the empty corridor between trials; it can run indefinitely without
	# hitting the finite fallback route or keeping old signals in memory.
	timeline.set_runner_cell(0)
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
	var definition: RunDefinition = game.get_node("RunManager").current_run
	var data := definition.BASIC_DOOR.duplicate(true) as SignalData
	data.set_meta("auto_codex_popups", false)
	data.system_id = "trial_%04d" % _sequence
	data.display_name = data.system_id
	data.puzzle = null
	data.ic_modules = ICComponent.new()
	data.detection.delay = settings.breach_delay_sec
	if case.puzzle != "none":
		data.puzzle = definition.make_fuzz_puzzle(case.difficulty, settings.fuzz_config) if case.puzzle == "fuzz" else definition.build_puzzle(case.puzzle, case.difficulty)
		data.puzzle.set_custom_fixed()
	for module in case.ic:
		var ic = definition.build_ic(module.ic, module.difficulty)
		ic.set_custom_fixed()
		data.ic_modules.add_module(ic)
	signal_manager.spawn_signal_data(data, timeline.screen_x_to_cell(timeline.screen_width + 80))
	current = signal_manager.signal_queue[-1]
	var config := PlaytestRecorder.configuration(data)
	config["breach_delay_sec"] = settings.breach_delay_sec
	config["runner_speed"] = settings.runner_speed
	config["shuffle_seed"] = settings.shuffle_seed
	config["coverage"] = "sampled" if sampler.sampled_combinations else "shuffled_matrix"
	_current_trial = recorder.watch_signal(current, config, repeat_of)
	_current_case = case.duplicate(true)
	signal_manager.update_signal_position()
	CommandDispatch.terminal_window.command_line.grab_focus()

func _trial_finished(summary: Dictionary) -> void:
	last_case = _current_case.duplicate(true)
	last_trial = summary.trial
	if summary.outcome == "success":
		_successes += 1
	elif summary.outcome == "breached":
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
	game.get_node("WindowManager").close_puzzles_for_signal(sig, false)
	game.get_node("WindowManager").clear_focus_overlay()
	game.get_node("SignalTimeline/ScanController").notify_signal_despawned(sig)
	var terminal = CommandDispatch.terminal_window
	if sig.terminal_session != null:
		terminal._close_session_tab(sig.terminal_session, sig)
	sig.release_run_state()
	if sig.instance_node != null and is_instance_valid(sig.instance_node):
		sig.data.ic_modules.notify_visuals_cleared(sig)
		sig.instance_node.queue_free()
		sig.instance_node = null
	signal_manager.signal_queue.erase(sig)

func repeat_last() -> void:
	if (last_case.is_empty() and current == null) or ended:
		return
	_repeat_case = last_case.duplicate(true) if not last_case.is_empty() else _current_case.duplicate(true)
	_repeat_of = last_trial if not last_case.is_empty() else _current_trial
	_repeat_requested = true
	if current != null:
		recorder.finish_trial(current, "repeated", "ignored")
	elif not _transitioning:
		delay.start(maxf(0.001, settings.next_delay_sec))

func skip_trial() -> void:
	if current != null and not ended:
		recorder.finish_trial(current, "skipped", "ignored")

func end_session() -> void:
	if ended or not started:
		return
	ended = true
	delay.stop()
	recorder.end_session("complete")
	clear_current()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	$HUD/Settings.hide()
	get_tree().paused = false
	$HUD/Bar/Rows/Output.text = "SAVED // " + ProjectSettings.globalize_path(recorder.output_path) + " (+ CSV)"

func _exit_tree() -> void:
	ended = true
	get_tree().paused = false
