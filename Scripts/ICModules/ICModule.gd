# ICModule.gd
# Base class for IC modules

class_name ICModule extends Resource

@export var codex_id: StringName
@export var warning_msg: String = "Unknown IC"

@export_storage var base_difficulty: int = 0
@export_storage var uses_escalation_difficulty: bool = true

func _init():
	#NOTE: This seems to work
	warning_msg = get_desc()

# Virtual function to be overridden
func get_desc():
	return ""

func get_codex_id():
	return &""

func warning_notice() -> String:
	return warning_msg

func bind_to_context(signal_data: SignalData, terminal_ref: Control):
	pass

func set_difficulty(_difficulty: int) -> void:
	print("Setting difficulty on : " + str(_difficulty))
	base_difficulty = _difficulty
	uses_escalation_difficulty = true
	apply_difficulty(_difficulty)

func apply_difficulty(_difficulty: int) -> void:
	pass
	
func apply_escalation(escalation_level: int) -> void:
	if not uses_escalation_difficulty:
		return
	var effective_difficulty = base_difficulty + escalation_level
	apply_difficulty(effective_difficulty)

func set_custom_fixed() -> void:
	uses_escalation_difficulty = false

func apply_params(_params: Dictionary) -> void:
	pass

func process_action(_action_context: ActionContext) -> void:
	pass

func postprocess_action(_action_context: ActionContext) -> void:
	pass

# Called for actions targeting a *different* signal while the host signal
# has an open terminal session. Lets session-scoped IC (e.g. Tether) veto
# or react to what the player does elsewhere.
func process_external_action(_action_context: ActionContext, _host_sig: ActiveSignal) -> void:
	pass

func postprocess_external_action(_action_context: ActionContext, _host_sig: ActiveSignal) -> void:
	pass

func on_connect(active_sig: ActiveSignal):
	pass

func on_initialized(active_sig: ActiveSignal):
	pass

func on_session_closed(active_sig: ActiveSignal):
	pass

func on_disabled(active_sig: ActiveSignal):
	pass

func on_enabled(active_sig: ActiveSignal):
	pass

func on_visuals_ready(_active_sig: ActiveSignal, _ic_effects: ICEffectsHost, _module_index: int) -> void:
	pass

func on_visuals_cleared(_active_sig: ActiveSignal) -> void:
	pass

func get_connection_flow_lines(_active_sig: ActiveSignal) -> Array[String]:
	return []

# Queues an IC-sourced heat spike against `active_sig`.
func _queue_heat(active_sig: ActiveSignal, amount: float, tag: StringName, source_label: String) -> void:
	if active_sig == null or amount <= 0.0:
		return
	var action := ActionContext.create_system_action(
		ActionContext.ActionType.ADD_HEAT,
		active_sig,
		ActionContext.SourceType.IC_MODULE
	)
	action.heat_delta = amount
	action.add_tag(&"ic")
	action.add_tag(tag)
	action.set_metadata(&"codex_id", get_codex_id())
	action.set_metadata(&"heat_source", source_label)
	ActionResolver.enqueue_action(action)
	GlobalEvents.ic_triggered.emit(String(tag))

# Prints a one-off IC notice in the terminal.
func _notify(text: String) -> void:
	if CommandDispatch.terminal_window == null:
		return
	CommandDispatch.terminal_window.print_transient(text)

# True for actions the player caused (terminal commands or programs),
# including follow-ups such as KILL -> DISABLE_SIGNAL.
func _is_player_action(action_context: ActionContext) -> bool:
	if action_context == null:
		return false
	return action_context.root_action_source == ActionContext.SourceType.TERMINAL_COMMAND \
		or action_context.root_action_source == ActionContext.SourceType.PROGRAM

func _pick_difficulty_value(values: Array, difficulty: int):
	if values.is_empty():
		return null
	var clamped_index := clampi(difficulty - 1, 0, values.size() - 1)
	return values[clamped_index]
