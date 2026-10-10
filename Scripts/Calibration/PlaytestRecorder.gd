class_name PlaytestRecorder extends Node

signal trial_finished(summary: Dictionary)
signal storage_failed(message: String)

@export var output_directory := "user://telemetry"
@export var auto_record_visible_signals := false
@export var tester := "tester"
@export var skill_tag := "unspecified"

var session := ""
var run_id := "gauntlet"
var output_path := ""
var csv_path := ""
var game_clock := 0.0
var wall_clock := 0.0
var records: Array[Dictionary] = []
var active: Dictionary = {} # Instance id -> runtime observation; not serialized.
var _jsonl: FileAccess
var _csv: FileAccess
var _ticks := 0
var _trial_number := 0
var _pending: Dictionary = {}
var _finished := false
var _was_paused := false
var _speed_mode := ""

const CSV_FIELDS := ["session", "tester", "skill", "trial", "signal", "outcome", "case_key", "repeat_of", "visible_to_clear_sec", "interaction_to_clear_sec", "visible_to_end_sec", "interaction_to_end_sec", "spawn_to_end_sec", "game_duration_sec", "hold_sec", "command_count", "failed_commands", "puzzle_attempts", "puzzle_errors", "ic_events", "heat", "null_spike_used", "programs_used", "config_json"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ticks = Time.get_ticks_usec()
	ActionResolver.action_started.connect(_action_started)
	ActionResolver.action_resolved.connect(_action_resolved)
	ActionResolver.action_failed.connect(_action_failed)
	CommandDispatch.command_submitted.connect(_command_submitted)
	CommandDispatch.command_error.connect(_command_error)
	GlobalEvents.telemetry_event.connect(_observation)
	GlobalEvents.signal_scanned.connect(_scan_layer)
	GlobalEvents.signal_scan_complete.connect(func(data: SignalData): _data_event(data, "scan_complete"))
	GlobalEvents.signal_connect.connect(func(data: SignalData): _data_event(data, "connected"))
	GlobalEvents.puzzle_started.connect(_puzzle_opened)
	GlobalEvents.puzzle_solved.connect(func(data: SignalData): _data_event(data, "puzzle_solved"))
	GlobalEvents.puzzle_failed.connect(func(data: SignalData): _data_event(data, "puzzle_failed"))
	GlobalEvents.signal_breached.connect(func(sig: ActiveSignal): finish_trial(sig, "breached", "breached"))
	GlobalEvents.heat_increased.connect(_heat)
	GlobalEvents.runners_damaged.connect(func(amount: float):
		if active.size() == 1:
			observe(active.values()[0].sig, "runner_damage", {"damage": amount})
	)
	GlobalEvents.runner_hold_count_changed.connect(_holds)
	GlobalEvents.runner_detected.connect(func(sig: ActiveSignal): observe(sig, "detected", {"by": sig.data.system_id, "heat_delta": 0.0}))
	GlobalEvents.activate_null_spike.connect(func(): _mark_null_spike())
	GlobalEvents.program_executed.connect(_program_executed)
	if CommandDispatch.terminal_window != null:
		CommandDispatch.terminal_window.session_closed.connect(_session_closed)
	if auto_record_visible_signals:
		var manager = CommandDispatch.timeline_manager.get_node_or_null("../../RunManager") if CommandDispatch.timeline_manager != null else null
		var name := String(manager.current_run.get_run_id()) if manager != null and manager.current_run != null else "normal_play"
		start_session(tester, skill_tag, {"mode": "normal_play"}, name)

func start_session(tester_name: String, skill: String, settings: Dictionary = {}, run_name: String = "gauntlet") -> bool:
	tester = tester_name
	skill_tag = skill
	run_id = run_name
	session = Time.get_datetime_string_from_system().replace(":", "-") + "-%d" % Time.get_ticks_usec()
	game_clock = 0.0
	wall_clock = 0.0
	_ticks = Time.get_ticks_usec()
	_was_paused = get_tree().paused
	_finished = false
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	if error != OK:
		storage_failed.emit("Cannot create telemetry directory (%d)." % error)
		session = ""
		return false
	output_path = output_directory.path_join(session + ".jsonl")
	csv_path = output_directory.path_join(session + ".csv")
	_jsonl = FileAccess.open(output_path, FileAccess.WRITE)
	_csv = FileAccess.open(csv_path, FileAccess.WRITE)
	if _jsonl == null or _csv == null:
		storage_failed.emit("Cannot open telemetry output files.")
		_jsonl = null
		_csv = null
		session = ""
		return false
	_csv.store_csv_line(PackedStringArray(CSV_FIELDS))
	write_event("run_started", null, {"tester": tester, "skill": skill_tag, "settings": settings, "heat": _current_heat(), "schema_version": 1, "clock_notes": "t = pause-excluded game time; wall_t = pause-excluded real time"})
	return true

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_delta := float(now - _ticks) / 1000000.0
	_ticks = now
	if session.is_empty() or _finished:
		return
	var paused := get_tree().paused
	if paused != _was_paused:
		write_event("pause_started" if paused else "pause_ended")
		_was_paused = paused
	if paused:
		return
	advance_clock(delta, real_delta)
	var timeline = CommandDispatch.timeline_manager
	if timeline == null:
		return
	var mode := _get_speed_mode()
	if mode != _speed_mode:
		_speed_mode = mode
		write_event("speed_changed", null, {"time_scale": Engine.time_scale})
	if auto_record_visible_signals and CommandDispatch.signal_manager != null:
		for sig in CommandDispatch.signal_manager.signal_queue:
			if sig.instance_node != null and not sig.is_disabled and not sig.data.has_meta("telemetry_seen"):
				var x: float = timeline.cell_to_screen_x(sig.start_cell_index)
				if x >= 0.0 and x <= timeline.screen_width:
					sig.data.set_meta("telemetry_seen", true)
					watch_signal(sig, configuration(sig.data))
	for trial in active.values():
		var sig: ActiveSignal = trial.sig
		var x: float = timeline.cell_to_screen_x(sig.start_cell_index)
		if trial.visible == null and sig.instance_node != null and x >= 0.0 and x <= timeline.screen_width:
			observe(sig, "signal_visible")

func advance_clock(game_delta: float, wall_delta: float) -> void:
	if get_tree().paused:
		return
	game_clock += game_delta
	wall_clock += wall_delta

func watch_signal(sig: ActiveSignal, config: Dictionary, repeat_of: int = 0) -> int:
	_trial_number += 1
	active[sig.get_instance_id()] = {"sig": sig, "trial": _trial_number, "config": config, "repeat_of": repeat_of, "started": wall_clock, "game_started": game_clock, "visible": null, "interaction": null, "hold_start": null, "hold_sec": 0.0, "commands": 0, "failed_commands": 0, "puzzle_attempts": 0, "puzzle_errors": 0, "ic_events": 0, "heat": 0.0, "null_spike_used": false, "programs_used": [], "disconnect_reason": "player"}
	observe(sig, "trial_started", {"config": config, "repeat_of": repeat_of})
	return _trial_number

func observe(sig: ActiveSignal, event: String, details: Dictionary = {}) -> void:
	var trial := _trial(sig)
	if trial.is_empty():
		return
	if event == "signal_visible" and trial.visible == null:
		trial.visible = wall_clock
	if event in ["scan_started", "command_started", "connected"] and trial.interaction == null:
		trial.interaction = wall_clock
	if event == "command":
		trial.commands += 1
		if not details.get("ok", false):
			trial.failed_commands += 1
	if event == "puzzle_opened":
		trial.puzzle_attempts += 1
	if event == "puzzle_input" and not details.get("ok", true):
		trial.puzzle_errors += 1
	if event == "ic_triggered":
		trial.ic_events += 1
	write_event(event, sig, details)

func finish_trial(sig: ActiveSignal, outcome: String, how: String = "") -> void:
	var trial := _trial(sig)
	if trial.is_empty():
		return
	if trial.hold_start != null:
		trial.hold_sec += wall_clock - float(trial.hold_start)
	var visible_elapsed = wall_clock - float(trial.visible) if trial.visible != null else null
	var interaction_elapsed = wall_clock - float(trial.interaction) if trial.interaction != null else null
	var summary := {
		"session": session, "tester": tester, "skill": skill_tag,
		"trial": trial.trial, "signal": sig.data.system_id,
		"outcome": outcome, "how": how, "case_key": case_key(trial.config),
		"repeat_of": trial.repeat_of,
		"visible_to_clear_sec": visible_elapsed if outcome == "success" else null,
		"interaction_to_clear_sec": interaction_elapsed if outcome == "success" else null,
		"visible_to_end_sec": visible_elapsed, "interaction_to_end_sec": interaction_elapsed,
		"spawn_to_end_sec": wall_clock - trial.started,
		"game_duration_sec": game_clock - trial.game_started,
		"hold_sec": trial.hold_sec, "command_count": trial.commands,
		"failed_commands": trial.failed_commands, "puzzle_attempts": trial.puzzle_attempts,
		"puzzle_errors": trial.puzzle_errors, "ic_events": trial.ic_events,
		"heat": trial.heat, "null_spike_used": trial.null_spike_used, "config": trial.config
	}
	observe(sig, "signal_resolved", {"how": how, "outcome": outcome})
	summary["programs_used"] = trial.programs_used
	write_event("trial_ended", sig, summary)
	records.append(summary)
	if _csv != null:
		var row := PackedStringArray()
		for key in CSV_FIELDS:
			var value = JSON.stringify(summary.config) if key == "config_json" else summary.get(key)
			row.append("" if value == null else str(value))
		_csv.store_csv_line(row)
		_csv.flush()
	active.erase(sig.get_instance_id())
	if _pending.get("trial", {}) == trial:
		_pending = {}
	trial_finished.emit(summary)

func write_event(event: String, sig: ActiveSignal = null, details: Dictionary = {}) -> void:
	if session.is_empty() or _finished:
		return
	var timeline = CommandDispatch.timeline_manager
	var item := {"t": game_clock, "wall_t": wall_clock, "event": event, "session": session, "run": run_id, "tester": tester, "skill": skill_tag, "runner_progress": timeline.path_progress if timeline != null else 0.0, "speed_mode": _get_speed_mode()}
	if sig != null and sig.data != null:
		item["signal"] = sig.data.system_id
		item["sig_type"] = SignalData.Type.keys()[sig.data.type]
		var trial := _trial(sig)
		if not trial.is_empty():
			item["trial"] = trial.trial
	item.merge(details, true)
	if _jsonl != null:
		_jsonl.store_line(JSON.stringify(item))
		_jsonl.flush()

func end_session(result: String = "quit") -> void:
	if _finished or session.is_empty():
		return
	for trial in active.values().duplicate():
		finish_trial(trial.sig, "interrupted", "ignored")
	write_event("run_ended", null, {"result": result, "heat": _current_heat(), "trials": records.size()})
	_finished = true
	_jsonl = null
	_csv = null

func _exit_tree() -> void:
	end_session("quit")

func _trial(sig: ActiveSignal) -> Dictionary:
	return active.get(sig.get_instance_id(), {}) if sig != null else {}

func _data_event(data: SignalData, event: String, details: Dictionary = {}) -> void:
	for trial in active.values():
		if trial.sig.data == data:
			var info := details.duplicate()
			if event.begins_with("puzzle_"):
				info.merge({"puzzle": trial.config.puzzle, "difficulty": trial.config.difficulty, "attempts": trial.puzzle_attempts}, false)
			observe(trial.sig, event, info)
			if event in ["puzzle_solved", "puzzle_failed"]:
				observe(trial.sig, "puzzle_closed", {"puzzle": trial.config.puzzle, "difficulty": trial.config.difficulty, "reason": event})
			return

func _scan_layer(data: SignalData, depth: int) -> void:
	for trial in active.values():
		if trial.sig.data == data:
			var index := depth - 1
			_data_event(data, "scan_layer_complete", {"layer_index": index, "layer": trial.sig.scan_layers[index].name, "duration_sec": trial.sig.scan_layers[index].duration})
			return

func _observation(sig: ActiveSignal, event: String, details: Dictionary) -> void:
	observe(sig, event, details)

func _puzzle_opened(sig: ActiveSignal, type: int) -> void:
	var details := {"puzzle": puzzle_key(type), "difficulty": sig.data.puzzle.difficulty, "attempts": _trial(sig).get("puzzle_attempts", 0) + 1}
	var manager = CommandDispatch.window_manager
	if manager != null:
		for window in manager._active_puzzle_windows:
			if manager._active_puzzle_windows[window] != sig:
				continue
			match type:
				PuzzleComponent.Type.FUZZ: details["target_angle_deg"] = rad_to_deg(window.state.sweet_spot_angle)
				PuzzleComponent.Type.SNIFF: details["targets"] = window.target_sequence
				PuzzleComponent.Type.DECRYPT: details["cipher"] = window.cipher_chars
	observe(sig, "puzzle_opened", details)

func _command_submitted(input: String, sig: ActiveSignal) -> void:
	var trial := _trial(sig)
	if trial.is_empty() and active.size() == 1:
		trial = active.values()[0]
	_pending = {"trial": trial, "recorded": false, "input": input}
	if not trial.is_empty():
		observe(trial.sig, "command_started", {"input": input})

func _command_error(message: String, sig: ActiveSignal) -> void:
	if _pending.get("recorded", false):
		return
	var trial: Dictionary = _pending.get("trial", _trial(sig))
	if not trial.is_empty():
		observe(trial.sig, "command", {"command": _pending.get("input", ""), "ok": false, "error": message, "blocked_by": [], "stage": "dispatch"})
	_pending["recorded"] = true

func _action_started(action: ActionContext) -> void:
	if action.action_type == ActionContext.ActionType.DISCONNECT_SESSION:
		var trial := _trial(action.primary_target)
		if not trial.is_empty():
			trial.disconnect_reason = String(action.get_metadata(&"codex_id", "player")).trim_prefix("codex_")
	observe(action.primary_target, "action_started", _action_details(action))

func _action_details(action: ActionContext) -> Dictionary:
	return {"action": ActionContext.ActionType.keys()[action.action_type], "source": ActionContext.SourceType.keys()[action.source_type], "command": action.command_name, "ok": action.was_successful(), "blocked_by": action.blocked_by, "tags": action.tags, "metadata": action.metadata, "heat_delta": action.heat_delta}

func _action_failed(action: ActionContext) -> void:
	observe(action.primary_target, "action_failed", _action_details(action))
	var blockers := action.blocked_by.duplicate()
	if action.action_type == ActionContext.ActionType.CALLBACK_INPUT:
		blockers.append(&"callback")
	for blocker in blockers:
		var key := String(blocker).trim_prefix("codex_")
		observe(action.primary_target, "ic_triggered", {"ic": key, "difficulty": _ic_difficulty(action.primary_target, key), "effect": "command_rejected"})
	_record_command_action(action)

func _record_command_action(action: ActionContext) -> void:
	if action.source_type != ActionContext.SourceType.TERMINAL_COMMAND or action.parent_action_type != ActionContext.ActionType.UNKNOWN:
		return
	observe(action.primary_target, "command", _action_details(action))
	_pending["recorded"] = true

func _action_resolved(action: ActionContext) -> void:
	var sig := action.primary_target
	observe(sig, "action_resolved", _action_details(action))
	_record_command_action(action)
	if action.source_type == ActionContext.SourceType.IC_MODULE:
		var key := String(action.get_metadata(&"codex_id", "")).trim_prefix("codex_")
		if key.is_empty() and not action.tags.is_empty():
			key = String(action.tags[-1])
		observe(sig, "ic_triggered", {"ic": key, "difficulty": _ic_difficulty(sig, key), "action": ActionContext.ActionType.keys()[action.action_type]})
	if action.action_type == ActionContext.ActionType.CALLBACK_INPUT:
		observe(sig, "ic_neutralized", {"ic": "callback", "difficulty": _ic_difficulty(sig, "callback")})
	if action.action_type == ActionContext.ActionType.TOGGLE_DOOR_LOCK and sig != null and not sig.data.door_locked:
		finish_trial(sig, "success", "unlocked")
	elif auto_record_visible_signals and action.action_type == ActionContext.ActionType.DISABLE_SIGNAL and action.root_action_source == ActionContext.SourceType.TERMINAL_COMMAND:
		finish_trial(sig, "success", "disabled")

func _heat(amount: float, source: String) -> void:
	# In an isolated gauntlet, all heat belongs to the active trial. In normal
	# play retain an unassigned event rather than guessing a host from text.
	if active.size() == 1:
		var trial: Dictionary = active.values()[0]
		trial.heat += amount
		observe(trial.sig, "heat", {"heat_delta": amount, "source": source})
	else:
		write_event("heat", null, {"heat_delta": amount, "source": source})

func _holds(count: int) -> void:
	for trial in active.values():
		if count > 0 and trial.hold_start == null:
			trial.hold_start = wall_clock
			observe(trial.sig, "hold_started")
		elif count == 0 and trial.hold_start != null:
			trial.hold_sec += wall_clock - float(trial.hold_start)
			trial.hold_start = null
			observe(trial.sig, "hold_ended")

func _mark_null_spike() -> void:
	for trial in active.values():
		trial.null_spike_used = true
		observe(trial.sig, "null_spike_started")

func _program_executed(program: ProgramInstance) -> void:
	for trial in active.values():
		trial.programs_used.append(String(program.get_program_id()))
		observe(trial.sig, "program_executed", {"program": String(program.get_program_id())})

func _session_closed(sig: ActiveSignal) -> void:
	var trial := _trial(sig)
	if not trial.is_empty():
		observe(sig, "disconnected", {"reason": trial.disconnect_reason})
		trial.disconnect_reason = "player"

func _get_speed_mode() -> String:
	var timeline = CommandDispatch.timeline_manager
	if timeline == null or is_zero_approx(timeline.cells_per_second):
		return "hold"
	return "hustle" if timeline.current_speed_mult > 1.0 else ("slow" if timeline.current_speed_mult < 1.0 else "walk")

func _current_heat() -> float:
	var timeline = CommandDispatch.timeline_manager
	var manager = timeline.get_node_or_null("../../HeatManager") if timeline != null else null
	return manager.current_heat if manager != null else 0.0

func _ic_difficulty(sig: ActiveSignal, key: String) -> int:
	if sig != null and sig.data.ic_modules != null:
		for module in sig.data.ic_modules.modules:
			if ic_key(module) == key:
				return module.base_difficulty
	return 0

static func puzzle_key(type: int) -> String:
	return {PuzzleComponent.Type.SNIFF: "sniff", PuzzleComponent.Type.DECRYPT: "decrypt", PuzzleComponent.Type.FUZZ: "fuzz"}.get(type, "none")

static func ic_key(module: Resource) -> String:
	return String(module.get_codex_id()).trim_prefix("codex_").to_lower()

static func resource_values(resource: Resource) -> Dictionary:
	var values := {}
	if resource == null:
		return values
	for property in resource.get_property_list():
		if not property.usage & PROPERTY_USAGE_STORAGE or property.name in ["script", "resource_name", "resource_local_to_scene"] or String(property.name).begins_with("_"):
			continue
		var value = resource.get(property.name)
		if value is Resource or value is Array and not value.is_empty() and value[0] is Resource:
			continue
		values[property.name] = value
	return values

static func configuration(data: SignalData) -> Dictionary:
	var config := {"puzzle": "none", "difficulty": 0, "ic": [], "resolved_puzzle": {}}
	if data.puzzle != null:
		config.puzzle = puzzle_key(data.puzzle.puzzle_type)
		config.difficulty = data.puzzle.difficulty if config.puzzle != "none" else 0
		var puzzle_config: Resource = data.puzzle.get_fuzz_config() if config.puzzle == "fuzz" else data.puzzle.puzzle_config
		config.resolved_puzzle = resource_values(puzzle_config)
	if data.ic_modules != null:
		for module in data.ic_modules.modules:
			config.ic.append({"ic": ic_key(module), "difficulty": module.base_difficulty, "resolved": resource_values(module)})
	return config

static func case_key(config: Dictionary) -> String:
	var pieces := PackedStringArray()
	if config.puzzle != "none":
		pieces.append("puzzle.%s.%d" % [config.puzzle, config.difficulty])
	for module in config.ic:
		pieces.append("ic.%s.%d" % [module.ic, module.difficulty])
	pieces.sort()
	return "+".join(pieces) if not pieces.is_empty() else "baseline"
