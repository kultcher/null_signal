class_name PlaytestRecorder extends Node

signal trial_finished(summary: Dictionary)
signal encounter_finished(summary: Dictionary)
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
# Encounter groups: several watched signals recorded as one unit.
var groups: Dictionary = {} # group id -> runtime group; not serialized.
var encounter_records: Array[Dictionary] = []
var _group_number := 0
var _encounter_csv: FileAccess
var _last_detector: ActiveSignal
var _last_finished := {} # {"kind": "trial"/"encounter", "id": ...} for ratings

const ENCOUNTER_CSV_FIELDS := ["session", "tester", "skill", "encounter", "template", "outcome", "wildcard", "difficulty", "lead_cells", "window_sec", "visible_to_pass_sec", "spawn_to_end_sec", "heat", "damage", "hold_sec", "predicted_total", "signals", "warmup", "session_index", "exposure", "added_ic", "ic_host_role", "disruption_counts"]
const TESTERS_DIR := "testers"
const LAST_TESTER_FILE := "last_tester.json"

const CSV_FIELDS := ["session", "tester", "skill", "trial", "signal", "outcome", "case_key", "repeat_of", "visible_to_clear_sec", "interaction_to_clear_sec", "visible_to_end_sec", "interaction_to_end_sec", "spawn_to_end_sec", "game_duration_sec", "hold_sec", "command_count", "failed_commands", "puzzle_attempts", "puzzle_errors", "ic_events", "heat", "null_spike_used", "programs_used", "config_json", "disruption_counts"]

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
	GlobalEvents.runners_damaged.connect(_damaged)
	GlobalEvents.runner_hold_count_changed.connect(_holds)
	GlobalEvents.runner_detected.connect(_detected)
	GlobalEvents.activate_null_spike.connect(func(): _mark_null_spike())
	GlobalEvents.program_executed.connect(_program_executed)
	if CommandDispatch.terminal_window != null:
		CommandDispatch.terminal_window.session_closed.connect(_session_closed)
		CommandDispatch.terminal_window.connection_ready.connect(func(sig: ActiveSignal): observe(sig, "connection_ready"))
		CommandDispatch.terminal_window.disruptions.effect_event.connect(_disruption_event)
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
	_encounter_csv = null
	encounter_records.clear()
	save_last_tester(tester, skill_tag)
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
				var x: float = timeline.cell_to_screen_x(sig.runtime_cell_x if sig.runtime_position_initialized else sig.start_cell_index)
				if x >= 0.0 and x <= timeline.screen_width:
					sig.data.set_meta("telemetry_seen", true)
					watch_signal(sig, configuration(sig.data))
	for trial in active.values():
		var sig: ActiveSignal = trial.sig
		# Mobile signals render at their runtime position, not their spawn cell.
		var cell: float = sig.runtime_cell_x if sig.runtime_position_initialized else sig.start_cell_index
		var x: float = timeline.cell_to_screen_x(cell)
		if trial.visible == null and sig.instance_node != null and x >= 0.0 and x <= timeline.screen_width:
			observe(sig, "signal_visible")

func advance_clock(game_delta: float, wall_delta: float) -> void:
	if get_tree().paused:
		return
	game_clock += game_delta
	wall_clock += wall_delta

func watch_signal(sig: ActiveSignal, config: Dictionary, repeat_of: int = 0, group_id: String = "") -> int:
	_trial_number += 1
	if groups.has(group_id):
		groups[group_id].trials.append(_trial_number)
	active[sig.get_instance_id()] = {"sig": sig, "trial": _trial_number, "group": group_id, "detected": false, "damage": 0.0, "config": config, "repeat_of": repeat_of, "started": wall_clock, "game_started": game_clock, "visible": null, "interaction": null, "hold_start": null, "hold_sec": 0.0, "commands": 0, "failed_commands": 0, "puzzle_attempts": 0, "puzzle_errors": 0, "ic_events": 0, "heat": 0.0, "null_spike_used": false, "programs_used": [], "disconnect_reason": "player", "disruption_counts": {}}
	observe(sig, "trial_started", {"config": config, "repeat_of": repeat_of})
	return _trial_number

func observe(sig: ActiveSignal, event: String, details: Dictionary = {}) -> void:
	var trial := _trial(sig)
	if trial.is_empty():
		return
	if event == "signal_visible" and trial.visible == null:
		trial.visible = wall_clock
		if groups.has(trial.group) and groups[trial.group].first_visible == null:
			groups[trial.group].first_visible = wall_clock
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
		"heat": trial.heat, "null_spike_used": trial.null_spike_used, "config": trial.config,
		"group": trial.group, "detected": trial.detected, "damage": trial.damage,
		"disruption_counts": trial.disruption_counts.duplicate()
	}
	observe(sig, "signal_resolved", {"how": how, "outcome": outcome})
	summary["programs_used"] = trial.programs_used
	write_event("trial_ended", sig, summary)
	records.append(summary)
	if _csv != null:
		var row := PackedStringArray()
		for key in CSV_FIELDS:
			var value = JSON.stringify(summary.config) if key == "config_json" else summary.get(key)
			if value is Dictionary or value is Array:
				value = JSON.stringify(value)
			row.append("" if value == null else str(value))
		_csv.store_csv_line(row)
		_csv.flush()
	active.erase(sig.get_instance_id())
	if _pending.get("trial", {}) == trial:
		_pending = {}
	if trial.group.is_empty():
		_last_finished = {"kind": "trial", "id": trial.trial}
	else:
		var group: Dictionary = groups.get(trial.group, {})
		if not group.is_empty():
			group.results.append({"signal": sig.data.system_id, "role": trial.config.get("role", ""), "outcome": outcome, "how": how, "heat": trial.heat, "detected": trial.detected, "disruption_counts": trial.disruption_counts.duplicate()})
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
	for group_id in groups.keys().duplicate():
		end_group(group_id, "interrupted")
	write_event("run_ended", null, {"result": result, "heat": _current_heat(), "trials": records.size(), "encounters": encounter_records.size()})
	_finished = true
	_jsonl = null
	_csv = null
	_encounter_csv = null

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

func _disruption_event(sig: ActiveSignal, effect: StringName, phase: StringName, details: Dictionary) -> void:
	var trial := _trial(sig)
	if trial.is_empty():
		return
	var key := "%s.%s" % [effect, phase]
	trial.disruption_counts[key] = int(trial.disruption_counts.get(key, 0)) + 1
	# The first queued key is an interaction, even though Lag has not yet
	# delivered a command to the resolver. Retain its actual timestamp.
	if effect == &"lag" and phase == &"queued" and trial.interaction == null:
		trial.interaction = wall_clock
	var observation := details.duplicate()
	observation.merge({"ic": String(effect), "difficulty": _ic_difficulty(sig, String(effect)), "phase": String(phase)}, true)
	observe(sig, "ic_disruption", observation)

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
	# Detection heat names its host ("Detected by <name>."): attribute it there.
	# Otherwise, in an isolated gauntlet all heat belongs to the only active
	# trial; with several active, keep it on their shared encounter if any,
	# else as an unassigned run-level event.
	var trial := _trial_for_source(source)
	if trial.is_empty() and active.size() == 1:
		trial = active.values()[0]
	if not trial.is_empty():
		trial.heat += amount
		if groups.has(trial.group):
			groups[trial.group].heat += amount
		observe(trial.sig, "heat", {"heat_delta": amount, "source": source})
		return
	var group_id := _single_active_group()
	if not group_id.is_empty():
		groups[group_id].heat += amount
		write_event("heat", null, {"heat_delta": amount, "source": source, "encounter": group_id})
	else:
		write_event("heat", null, {"heat_delta": amount, "source": source})

func _trial_for_source(source: String) -> Dictionary:
	if not source.begins_with("Detected by "):
		return {}
	var name := source.trim_prefix("Detected by ").trim_suffix(".")
	for trial in active.values():
		if trial.sig.data != null and (trial.sig.data.display_name == name or trial.sig.data.system_id == name):
			return trial
	return {}

func _single_active_group() -> String:
	var found := ""
	for trial in active.values():
		if trial.group.is_empty():
			return ""
		if found.is_empty():
			found = trial.group
		elif found != trial.group:
			return ""
	return found

func _detected(sig: ActiveSignal) -> void:
	_last_detector = sig
	var trial := _trial(sig)
	if not trial.is_empty():
		trial.detected = true
	observe(sig, "detected", {"by": sig.data.system_id, "heat_delta": 0.0})

# Damage carries no source: credit the signal that most recently detected the
# runner if it is still watched, else the only active trial.
func _damaged(amount: float) -> void:
	var trial := _trial(_last_detector) if _last_detector != null and is_instance_valid(_last_detector) else {}
	if trial.is_empty() and active.size() == 1:
		trial = active.values()[0]
	if trial.is_empty():
		var group_id := _single_active_group()
		if not group_id.is_empty():
			groups[group_id].damage += amount
		write_event("runner_damage", null, {"damage": amount, "encounter": group_id})
		return
	trial.damage += amount
	if groups.has(trial.group):
		groups[trial.group].damage += amount
	observe(trial.sig, "runner_damage", {"damage": amount})

func _holds(count: int) -> void:
	for group in groups.values():
		if count > 0 and group.hold_start == null:
			group.hold_start = wall_clock
		elif count == 0 and group.hold_start != null:
			group.hold_sec += wall_clock - float(group.hold_start)
			group.hold_start = null
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
	config["host"] = SignalData.Type.keys()[data.type].to_lower()
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
	if config.has("template"):
		pieces.append("enc.%s.%s" % [config.template, config.get("role", "signal")])
	if config.puzzle != "none":
		pieces.append("puzzle.%s.%d" % [config.puzzle, config.difficulty])
	for module in config.ic:
		pieces.append("ic.%s.%d" % [module.ic, module.difficulty])
	pieces.sort()
	return "+".join(pieces) if not pieces.is_empty() else "baseline"

# --- encounter groups ---

# Starts a group of trials recorded as one encounter. `info` carries the
# template, wildcard, lead/window, prediction and session bookkeeping.
func begin_group(info: Dictionary) -> String:
	_group_number += 1
	var group_id := "enc_%04d" % _group_number
	groups[group_id] = {"id": group_id, "info": info, "trials": [], "results": [], "started": wall_clock, "game_started": game_clock, "heat": 0.0, "damage": 0.0, "hold_sec": 0.0, "hold_start": null, "first_visible": null}
	write_event("encounter_started", null, {"encounter": group_id, "info": info})
	return group_id

# Ends a group: members still active are finished as "passed" (how: "seen" if
# they detected the runner, else "evaded"). Outcome, worst first: interrupted
# hints, damaged, breached, heated, clean.
func end_group(group_id: String, hint: String = "") -> Dictionary:
	if not groups.has(group_id):
		return {}
	var group: Dictionary = groups[group_id]
	for trial in active.values().duplicate():
		if trial.group == group_id:
			var how := "seen" if trial.detected or trial.heat > 0.0 else "evaded"
			finish_trial(trial.sig, hint if not hint.is_empty() else "passed", how)
	if group.hold_start != null:
		group.hold_sec += wall_clock - float(group.hold_start)
	var first_visible = group.first_visible
	var outcome := hint
	if outcome.is_empty():
		var breached: bool = group.results.any(func(r): return r.outcome == "breached")
		if group.damage > 0.0:
			outcome = "damaged"
		elif breached:
			outcome = "breached"
		elif group.heat > 0.0:
			outcome = "heated"
		else:
			outcome = "clean"
	var info: Dictionary = group.info
	var disruption_counts := {}
	for result in group.results:
		for key in result.get("disruption_counts", {}):
			disruption_counts[key] = int(disruption_counts.get(key, 0)) + int(result.disruption_counts[key])
	var summary := {
		"session": session, "tester": tester, "skill": skill_tag,
		"encounter": group_id, "template": info.get("template", ""), "outcome": outcome,
		"wildcard": info.get("wildcard", {}), "difficulty": info.get("difficulty", 0),
		"lead_cells": info.get("lead_cells", -1.0), "window_sec": info.get("window_sec", null),
		"visible_to_pass_sec": (wall_clock - float(first_visible)) if first_visible != null else null,
		"spawn_to_end_sec": wall_clock - group.started,
		"heat": group.heat, "damage": group.damage, "hold_sec": group.hold_sec,
		"predicted_total": info.get("predicted_total", null), "signals": group.results,
		"warmup": info.get("warmup", false), "session_index": info.get("session_index", 0),
		"exposure": info.get("exposure", {}), "info": info,
		"added_ic": info.get("added_ic", []), "ic_host_role": info.get("ic_host_role", ""),
		"disruption_counts": disruption_counts,
	}
	write_event("encounter_ended", null, summary)
	encounter_records.append(summary)
	_write_encounter_row(summary)
	groups.erase(group_id)
	_last_finished = {"kind": "encounter", "id": group_id}
	encounter_finished.emit(summary)
	return summary

func _write_encounter_row(summary: Dictionary) -> void:
	if session.is_empty() or _finished:
		return
	if _encounter_csv == null:
		_encounter_csv = FileAccess.open(output_directory.path_join(session + "_encounters.csv"), FileAccess.WRITE)
		if _encounter_csv == null:
			return
		_encounter_csv.store_csv_line(PackedStringArray(ENCOUNTER_CSV_FIELDS))
	var row := PackedStringArray()
	for key in ENCOUNTER_CSV_FIELDS:
		var value = summary.get(key)
		if value is Dictionary or value is Array:
			value = JSON.stringify(value)
		row.append("" if value == null else str(value))
	_encounter_csv.store_csv_line(row)
	_encounter_csv.flush()

# --- ratings ---

# Felt difficulty for the most recently finished trial or encounter
# (1 easy, 2 fine, 3 hard). Returns false when there is nothing to rate.
func rate_last(value: int) -> bool:
	if _last_finished.is_empty() or session.is_empty():
		return false
	var details := {"rating": clampi(value, 1, 3), "target": _last_finished.kind}
	if _last_finished.kind == "trial":
		details["trial"] = _last_finished.id
	else:
		details["encounter"] = _last_finished.id
	write_event("rating", null, details)
	_last_finished = {}
	return true

# --- exposure counts and tester memory (persist across sessions) ---

# Element keys for a configuration: "puzzle.sniff", "ic.bouncer",
# "enc.camera_corridor". Tiers are ignored: exposure is about familiarity.
static func exposure_keys(config: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	if config.has("template"):
		keys.append("enc." + String(config.template))
	if String(config.get("puzzle", "none")) != "none":
		keys.append("puzzle." + String(config.puzzle))
	for module in config.get("ic", []):
		keys.append("ic." + String(module.ic))
	return keys

func _tester_path(name: String) -> String:
	var safe := name.strip_edges().to_lower().validate_filename().replace(" ", "_")
	return output_directory.path_join(TESTERS_DIR).path_join((safe if not safe.is_empty() else "tester") + ".json")

func load_exposure(name: String = tester) -> Dictionary:
	var parsed = _read_json(_tester_path(name))
	return parsed.get("exposure", {}) if parsed is Dictionary else {}

static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	return JSON.parse_string(text) if not text.strip_edges().is_empty() else null

# Returns counts before this encounter and records one more exposure for each.
func take_exposure(keys: Array[String]) -> Dictionary:
	var counts := load_exposure()
	var before := {}
	for key in keys:
		before[key] = int(counts.get(key, 0))
		counts[key] = before[key] + 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory.path_join(TESTERS_DIR)))
	var file := FileAccess.open(_tester_path(tester), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"tester": tester, "exposure": counts}, "\t"))
	return before

func save_last_tester(name: String, skill: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	var file := FileAccess.open(output_directory.path_join(LAST_TESTER_FILE), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"tester": name, "skill": skill}))

func load_last_tester() -> Dictionary:
	var parsed = _read_json(output_directory.path_join(LAST_TESTER_FILE))
	return parsed if parsed is Dictionary else {}
