extends Node

signal action_started(action_context: ActionContext)
signal action_resolved(action_context: ActionContext)
signal action_failed(action_context: ActionContext)

var _pending_actions: Array[ActionContext] = []
var _is_processing_actions := false
const DEBUG_PREFIX := "[ActionResolver]"

# Per-action trace output. Noisy; flip off when not debugging the pipeline.
var debug_logging := true

func reset_run_state() -> void:
	_pending_actions.clear()
	_is_processing_actions = false

func build_scan_action(target_signal: ActiveSignal) -> ActionContext:
	var action := ActionContext.create_system_action(
		ActionContext.ActionType.START_SCAN_SIGNAL,
		target_signal
	)
	action.add_tag(&"scan")
	action.set_metadata(&"scan_time_multiplier", 1.0)
	action.ensure_lineage_defaults()
	_debug_action("build", action, "for scan start")
	return action

func build_action_from_command(cmd_context: CommandContext) -> ActionContext:
	var action := ActionContext.from_command(cmd_context)
	if cmd_context == null:
		action.fail("Invalid action context.")
		return action

	match cmd_context.command:
		"KILL":
			action.action_type = ActionContext.ActionType.KILL_SIGNAL
			action.add_tag(&"hostile")
			action.add_tag(&"terminal")
			action.heat_delta = 500.0
		"PROBE":
			action.action_type = ActionContext.ActionType.PROBE_SIGNAL
			action.add_tag(&"terminal")
		"OP":
			if cmd_context.active_sig != null and cmd_context.active_sig.data != null:
				match cmd_context.active_sig.data.type:
					SignalData.Type.DOOR:
						action.action_type = ActionContext.ActionType.TOGGLE_DOOR_LOCK
					SignalData.Type.DISRUPTOR:
						action.action_type = ActionContext.ActionType.ACTIVATE_DISRUPTOR
					_:
						action.action_type = ActionContext.ActionType.UNKNOWN
						action.fail("Invalid context, no operation available.")
			else:
				action.action_type = ActionContext.ActionType.UNKNOWN
				action.fail("Invalid context, no operation available.")
		"RUN":
			action.action_type = ActionContext.ActionType.LAUNCH_PUZZLE
		"ACCESS":
			action.action_type = ActionContext.ActionType.ACCESS_SIGNAL
			action.add_tag(&"terminal")
			action.set_metadata(&"show_connection_banner", true)
		"HELP":
			action.action_type = ActionContext.ActionType.SHOW_HELP
			action.add_tag(&"terminal")
		"CALLBACK":
			action.action_type = ActionContext.ActionType.CALLBACK_INPUT
			action.add_tag(&"terminal")
			action.add_tag(&"callback")
			action.set_metadata(&"callback_input", cmd_context.arg)
		_:
			action.action_type = ActionContext.ActionType.UNKNOWN
			action.fail("Unsupported action.")

	action.ensure_lineage_defaults()
	_debug_action("build", action, "from command " + str(cmd_context.command))
	return action

# Resolves an action *now* and returns it with its final status. Callers
# (terminal commands, scan starts) read the result immediately, so this must
# not be deferred even if another action is mid-resolution: if the queue is
# already draining, the action is resolved nested, right away. Follow-up
# actions it spawns still go through the queue.
func resolve_action(action_context: ActionContext) -> ActionContext:
	if action_context == null:
		return null

	_debug_action("resolve_request", action_context)
	action_context.ensure_lineage_defaults()
	if _is_processing_actions:
		# Resolve it and the follow-ups it queues before handing it back;
		# actions that were already pending keep their place.
		var first_followup := _pending_actions.size()
		_resolve_single_action(action_context)
		while _pending_actions.size() > first_followup:
			_resolve_single_action(_pending_actions.pop_at(first_followup))
		return action_context
	enqueue_action(action_context)
	return action_context

func enqueue_action(action_context: ActionContext) -> ActionContext:
	if action_context == null:
		return null

	action_context.ensure_lineage_defaults()
	_pending_actions.append(action_context)
	_debug_action("enqueue", action_context, "queue_size=" + str(_pending_actions.size()))
	if not _is_processing_actions:
		_drain_action_queue()
	return action_context

func _drain_action_queue() -> void:
	if _is_processing_actions:
		return

	_is_processing_actions = true
	while not _pending_actions.is_empty():
		var action_context = _pending_actions.pop_front()
		_debug_action("dequeue", action_context, "remaining=" + str(_pending_actions.size()))
		_resolve_single_action(action_context)
	_is_processing_actions = false

func _resolve_single_action(action_context: ActionContext) -> void:
	if action_context == null:
		return

	action_context.mark_processing()
	_debug_action("start", action_context)
	action_started.emit(action_context)

	_run_preprocessors(action_context)
	if action_context.was_unsuccessful():
		_debug_action("halted_pre", action_context)
		_emit_terminal_outcome(action_context)
		return

	_apply_core_effect(action_context)
	_run_postprocessors(action_context)
	_debug_action("finish", action_context, "status=" + _status_to_string(action_context.status))
	_emit_terminal_outcome(action_context)

func _run_preprocessors(action_context: ActionContext) -> void:
	_debug_action("preprocess", action_context)
	ProgramManager.preprocess_action(action_context)
	var target := action_context.primary_target
	if target != null and target.data != null and target.data.ic_modules != null:
		target.data.ic_modules.process_action(action_context)
	if action_context.was_unsuccessful():
		return
	for observer in _get_session_observers(target):
		observer.data.ic_modules.process_external_action(action_context, observer)
		if action_context.was_unsuccessful():
			return

func _apply_core_effect(action_context: ActionContext) -> void:
	if action_context == null or action_context.was_unsuccessful():
		return

	_debug_action("core", action_context, _action_type_to_string(action_context.action_type))
	match action_context.action_type:
		ActionContext.ActionType.START_SCAN_SIGNAL:
			_apply_start_scan_signal(action_context)
		ActionContext.ActionType.ACCESS_SIGNAL:
			_apply_access_signal(action_context)
		ActionContext.ActionType.SHOW_HELP:
			_apply_show_help(action_context)
		ActionContext.ActionType.CALLBACK_INPUT:
			_apply_callback_input(action_context)
		ActionContext.ActionType.PROBE_SIGNAL:
			_apply_probe_signal(action_context)
		ActionContext.ActionType.KILL_SIGNAL:
			_apply_kill_signal(action_context)
		ActionContext.ActionType.ADD_HEAT:
			_apply_add_heat(action_context)
		ActionContext.ActionType.RAISE_GUARD_ALERT:
			_apply_raise_guard_alert(action_context)
		ActionContext.ActionType.DISABLE_SIGNAL:
			_apply_disable_signal(action_context)
		ActionContext.ActionType.ENABLE_SIGNAL:
			_apply_enable_signal(action_context)
		ActionContext.ActionType.DISCONNECT_SESSION:
			_apply_disconnect_session(action_context)
		ActionContext.ActionType.TOGGLE_DOOR_LOCK:
			_apply_toggle_door_lock(action_context)
		ActionContext.ActionType.LAUNCH_PUZZLE:
			_apply_launch_puzzle(action_context)
		ActionContext.ActionType.ACTIVATE_DISRUPTOR:
			_apply_activate_disruptor(action_context)
		_:
			action_context.fail("Unsupported action.")

func _run_postprocessors(action_context: ActionContext) -> void:
	_debug_action("postprocess", action_context)
	ProgramManager.postprocess_action(action_context)
	var target := action_context.primary_target
	if target != null and target.data != null and target.data.ic_modules != null:
		target.data.ic_modules.postprocess_action(action_context)
	for observer in _get_session_observers(target):
		observer.data.ic_modules.postprocess_external_action(action_context, observer)

# Signals other than `target` that have an open terminal session and IC.
# Their modules get to see (and veto) actions aimed elsewhere, which is how
# session-scoped IC like Tether work.
func _get_session_observers(target: ActiveSignal) -> Array[ActiveSignal]:
	var observers: Array[ActiveSignal] = []
	if CommandDispatch.signal_manager == null:
		return observers
	for sig in CommandDispatch.signal_manager.signal_queue:
		if sig == null or sig == target or sig.data == null or sig.data.ic_modules == null:
			continue
		if sig.terminal_session == null or not sig.terminal_session.has_tab:
			continue
		observers.append(sig)
	return observers

func _apply_access_signal(action_context: ActionContext) -> void:
	var target := action_context.primary_target
	if target == null or target.data == null:
		action_context.fail("Invalid context, no signal available.")
		return

	var show_connection_banner := bool(action_context.get_metadata(&"show_connection_banner", false))
	CommandDispatch.switch_terminal_session(target, show_connection_banner)
	action_context.succeed()

func _apply_start_scan_signal(action_context: ActionContext) -> void:
	if not _ensure_target_is_responding(action_context):
		return

	var scan_time_multiplier := float(action_context.get_metadata(&"scan_time_multiplier", 1.0))
	action_context.set_metadata(&"scan_time_multiplier", maxf(0.01, scan_time_multiplier))
	action_context.succeed()

func _apply_show_help(action_context: ActionContext) -> void:
	if CommandDispatch.window_manager != null:
		CommandDispatch.window_manager.show_help_overlay()
	action_context.succeed("Opening terminal reference.")

func _apply_callback_input(action_context: ActionContext) -> void:
	if action_context == null:
		return
	if action_context.was_successful():
		return
	action_context.fail("No callback channel available.")

func _ensure_target_is_responding(action_context: ActionContext) -> bool:
	var target := action_context.primary_target
	if target == null or target.data == null:
		action_context.fail("Invalid context, no signal available.")
		return false
	if target.is_disabled:
		action_context.fail("No response. Signal disabled.")
		return false
	return true

func _apply_probe_signal(action_context: ActionContext) -> void:
	if not _ensure_target_is_responding(action_context):
		return
	action_context.succeed()

func _apply_kill_signal(action_context: ActionContext) -> void:
	if not _ensure_target_is_responding(action_context):
		return

	var target := action_context.primary_target
	if target.data.type == SignalData.Type.DOOR:
		action_context.fail("KILL failed. No active process to kill on signal type: DOOR.")
		return

	var disable_action := ActionContext.create_followup_action(
		action_context,
		ActionContext.ActionType.DISABLE_SIGNAL,
		target
	)
	disable_action.command_context = action_context.command_context
	disable_action.command_name = action_context.command_name
	disable_action.heat_delta = action_context.heat_delta
	for tag in action_context.tags:
		disable_action.add_tag(tag)
	_debug_action("followup", disable_action, "derived from kill")
	enqueue_action(disable_action)
	action_context.succeed()

func _apply_add_heat(action_context: ActionContext) -> void:
	if action_context.heat_delta > 0.0:
		GlobalEvents.heat_increased.emit(action_context.heat_delta, str(action_context.get_metadata(&"heat_source", "")))
	action_context.succeed()

func _apply_raise_guard_alert(action_context: ActionContext) -> void:
	var alert: GuardAlertData = action_context.get_metadata(&"guard_alert", null)
	if alert == null:
		action_context.fail("Guard alert action missing payload.")
		return

	GlobalEvents.guard_alert_raised.emit(alert)
	action_context.succeed()

func _apply_disable_signal(action_context: ActionContext) -> void:
	if not _ensure_target_is_responding(action_context):
		return

	var target := action_context.primary_target
	if not _disable_signal_target(target, action_context):
		return
	if action_context.root_command_name == "KILL":
		action_context.succeed("Shutting down " + target.data.system_id + "...")
		GlobalEvents.signal_killed.emit(target)
		if action_context.heat_delta != 0.0:
			_queue_heat_action(
				action_context.heat_delta,
				"Shutting down " + target.data.system_id + ".",
				target,
				action_context
			)
		return
	action_context.succeed()

func _apply_enable_signal(action_context: ActionContext) -> void:
	var target := action_context.primary_target
	if target == null or target.data == null:
		action_context.fail("Invalid context, no signal available.")
		return
	if not target.is_disabled:
		action_context.succeed()
		return

	target.enable_signal()
	action_context.succeed()

func _apply_disconnect_session(action_context: ActionContext) -> void:
	var target := action_context.primary_target
	if target == null:
		action_context.fail("Invalid context, no signal available.")
		return
	if CommandDispatch.terminal_window == null:
		action_context.fail("Terminal window unavailable.")
		return
	if target.terminal_session == null or not target.terminal_session.has_tab:
		action_context.succeed()
		return

	var reason_lines: Array[String] = []
	var raw_reason_lines = action_context.get_metadata(&"reason_lines", [])
	for line in raw_reason_lines:
		reason_lines.append(str(line))
	CommandDispatch.terminal_window.force_disconnect_signal(target, reason_lines)
	action_context.succeed()

func _apply_toggle_door_lock(action_context: ActionContext) -> void:
	if not _ensure_target_is_responding(action_context):
		return

	var target := action_context.primary_target
	if target.data.type != SignalData.Type.DOOR:
		action_context.fail("Invalid context, no operation available.")
		return

	var new_locked := not target.data.door_locked
	target.set_door_locked(new_locked)
	if new_locked:
		action_context.succeed(target.data.display_name + " locked.")
	else:
		action_context.succeed(target.data.display_name + " unlocked.")

func _apply_launch_puzzle(action_context: ActionContext) -> void:
	var cmd_context := action_context.command_context
	if cmd_context == null:
		action_context.fail("RUN failed. Invalid action context.")
		return
	if not _ensure_target_is_responding(action_context):
		return

	var target := action_context.primary_target
	if target.data.puzzle == null:
		action_context.fail("RUN " + cmd_context.arg.to_upper() + " failed. Signal is not locked.")
		return
	if not target.data.puzzle.puzzle_locked:
		action_context.fail("RUN " + cmd_context.arg.to_upper() + " failed. Signal already unlocked.")
		return

	var program_name := cmd_context.arg
	var puzzle_type = target.data.puzzle.puzzle_type
	match puzzle_type:
		PuzzleComponent.Type.SNIFF:
			if program_name == "sniff":
				action_context.succeed("Launching SNIFF...")
				GlobalEvents.puzzle_started.emit(target, PuzzleComponent.Type.SNIFF)
				return
		PuzzleComponent.Type.FUZZ:
			if program_name == "fuzz":
				action_context.succeed("Launching FUZZ...")
				GlobalEvents.puzzle_started.emit(target, PuzzleComponent.Type.FUZZ)
				return
		PuzzleComponent.Type.DECRYPT:
			if program_name == "decrypt":
				action_context.succeed("Launching DECRYPT...")
				GlobalEvents.puzzle_started.emit(target, PuzzleComponent.Type.DECRYPT)
				return

	var mismatch := {
		"sniff": "SNIFF: No avaiable datastream.",
		"fuzz": "FUZZ: No vulnerability detected.",
		"decrypt": "DECRYPT: Signal not encrypted."
	}
	if not mismatch.has(program_name):
		action_context.fail("RUN failed. No program named " + program_name.to_upper() + " found.")
		return
	action_context.fail(mismatch[program_name])

func _apply_activate_disruptor(action_context: ActionContext) -> void:
	if not _ensure_target_is_responding(action_context):
		return

	var target := action_context.primary_target
	var signal_data := target.data
	if signal_data.type != SignalData.Type.DISRUPTOR:
		action_context.fail("Invalid context, no operation available.")
		return

	if signal_data.disruptor == null or not signal_data.disruptor.enabled:
		action_context.fail("OP failed. " + signal_data.display_name + " has no active disruption profile.")
		return
	if signal_data.disruptor.get_uses() <= 0:
		action_context.fail("OP failed. " + signal_data.display_name + ": no activations remaining.")
		return
	if CommandDispatch.signal_manager == null:
		action_context.fail("OP failed. Signal manager unavailable.")
		return

	var source_cell := target.start_cell_index
	if target.runtime_position_initialized:
		source_cell = target.runtime_cell_x
	var source_lane := signal_data.lane
	if target.runtime_position_initialized:
		source_lane = target.runtime_lane

	var range_cells := maxi(0, signal_data.disruptor.horizontal_range_cells)
	var max_alert_targets := maxi(1, signal_data.disruptor.max_alert_targets)
	var alerted_targets: int = 0
	var matched_targets: int = 0
	for other_sig in CommandDispatch.signal_manager.signal_queue:
		if other_sig == null or other_sig.data == null:
			continue
		if other_sig.is_disabled:
			continue
		if other_sig.data.mobility == null:
			continue
		if not signal_data.disruptor.matches_distraction_target(other_sig.data.type):
			continue

		var target_cell = other_sig.start_cell_index
		if other_sig.runtime_position_initialized:
			target_cell = other_sig.runtime_cell_x
		if absf(target_cell - source_cell) > float(range_cells):
			continue

		var alert_action := _create_guard_alert_action(
			action_context,
			target,
			other_sig,
			source_cell,
			source_lane
		)
		_debug_action("followup", alert_action, "alert_target=" + other_sig.data.system_id)
		enqueue_action(alert_action)
		matched_targets += 1
		alerted_targets += 1
		if alerted_targets >= max_alert_targets:
			break

	signal_data.disruptor.uses -= 1
	if signal_data.disruptor.get_uses() <= 0:
		var disable_action := ActionContext.create_followup_action(
			action_context,
			ActionContext.ActionType.DISABLE_SIGNAL,
			target
		)
		disable_action.set_metadata(&"disable_reason", "disruptor_depleted")
		_debug_action("followup", disable_action, "disruptor depleted")
		enqueue_action(disable_action)
	if matched_targets <= 0:
		action_context.succeed(signal_data.display_name + " activated. No valid targets in range.")
		return

	action_context.succeed(signal_data.display_name + " activated. Alerted " + str(matched_targets) + " target(s).")

func _emit_terminal_outcome(action_context: ActionContext) -> void:
	if action_context == null:
		return

	# Follow-ups (e.g. KILL -> DISABLE_SIGNAL) share the root command's
	# context. Successful steps add their lines; a failing step replaces the
	# log with its reason (the terminal shows the first line of a failure),
	# and once a command has failed a later successful step can't flip it back.
	var cmd_context := action_context.command_context
	if cmd_context != null:
		match action_context.status:
			ActionContext.Status.FAILURE, ActionContext.Status.BLOCKED:
				cmd_context.log_text = action_context.log_text.duplicate()
				cmd_context.status = CommandContext.CommandStatus.FAILURE
			ActionContext.Status.SUCCESS:
				if cmd_context.status != CommandContext.CommandStatus.FAILURE:
					cmd_context.log_text.append_array(action_context.log_text)
					cmd_context.status = CommandContext.CommandStatus.SUCCESS
			_:
				if cmd_context.status != CommandContext.CommandStatus.FAILURE:
					cmd_context.status = CommandContext.CommandStatus.PROCESS

	if action_context.was_unsuccessful():
		action_failed.emit(action_context)
	else:
		action_resolved.emit(action_context)

func _queue_heat_action(amount: float, source_text: String, target: ActiveSignal = null, source_action: ActionContext = null) -> void:
	var heat_action := ActionContext.create_followup_action(
		source_action,
		ActionContext.ActionType.ADD_HEAT,
		target,
		source_action.source_type if source_action != null else ActionContext.SourceType.SYSTEM
	)
	heat_action.heat_delta = amount
	heat_action.set_metadata(&"heat_source", source_text)
	_debug_action("followup", heat_action, "heat=" + str(amount))
	enqueue_action(heat_action)

func _create_guard_alert_action(
	source_action: ActionContext,
	source_signal: ActiveSignal,
	target_signal: ActiveSignal,
	target_cell_x: float,
	target_lane: int
) -> ActionContext:
	var alert_action := ActionContext.create_followup_action(
		source_action,
		ActionContext.ActionType.RAISE_GUARD_ALERT,
		target_signal,
		source_action.source_type if source_action != null else ActionContext.SourceType.SYSTEM
	)
	alert_action.add_tag(&"alert")
	alert_action.add_tag(&"distraction")
	alert_action.add_tag(&"guard")

	var alert := GuardAlertData.new()
	alert.source_type = GuardAlertData.SourceType.DISTRACTION
	if target_signal != null and target_signal.data != null:
		alert.target_signal_id = target_signal.data.system_id
		alert.target_instance_id = target_signal.get_instance_id()
	alert.target_cell_x = target_cell_x
	alert.target_lane = target_lane
	if source_signal != null and source_signal.data != null and source_signal.data.disruptor != null:
		alert.priority = source_signal.data.disruptor.severity
		alert.ttl_sec = source_signal.data.disruptor.ttl_sec
		alert.investigate_sec_override = source_signal.data.disruptor.investigate_duration_sec
		alert.source_id = source_signal.data.system_id
	alert.emitted_time_sec = Time.get_ticks_msec() / 1000.0
	alert_action.set_metadata(&"guard_alert", alert)
	return alert_action

func _disable_signal_target(target: ActiveSignal, action_context: ActionContext = null) -> bool:
	if target == null or target.data == null:
		if action_context != null:
			action_context.fail("Invalid context, no signal available.")
		return false
	if target.is_disabled:
		if action_context != null:
			action_context.fail("No response. Signal disabled.")
		return false

	target.disable_signal()
	return true

func _debug_action(stage: String, action_context: ActionContext, details: String = "") -> void:
	if not debug_logging:
		return
	if action_context == null:
		print(DEBUG_PREFIX + " [" + stage + "] <null>")
		return

	var target_id := "<none>"
	if action_context.primary_target != null and action_context.primary_target.data != null:
		target_id = action_context.primary_target.data.system_id

	var message := "%s [%s] type=%s source=%s root_cmd=%s target=%s" % [
		DEBUG_PREFIX,
		stage,
		_action_type_to_string(action_context.action_type),
		_source_type_to_string(action_context.source_type),
		action_context.root_command_name,
		target_id,
	]
	if not details.is_empty():
		message += " " + details
	print(message)

func _action_type_to_string(action_type: int) -> String:
	var names := ActionContext.ActionType.keys()
	if action_type < 0 or action_type >= names.size():
		return str(action_type)
	return names[action_type]

func _source_type_to_string(source_type: int) -> String:
	var names := ActionContext.SourceType.keys()
	if source_type < 0 or source_type >= names.size():
		return str(source_type)
	return names[source_type]

func _status_to_string(status: int) -> String:
	var names := ActionContext.Status.keys()
	if status < 0 or status >= names.size():
		return str(status)
	return names[status]
