# TripwireModule.gd
# Heat spike when the player disables the signal. Punishes killing first and
# scanning later: the right answer is usually to slip past instead.

class_name TripwireModule extends ICModule

@export var heat_spike_amount: float = 900.0

const DIFFICULTY_HEAT_SPIKES := [600.0, 900.0, 1200.0, 1600.0]

func get_desc():
	return "Tripwire(+%d)" % int(heat_spike_amount)

func get_codex_id():
	return &"codex_tripwire"

func apply_difficulty(difficulty: int) -> void:
	heat_spike_amount = float(_pick_difficulty_value(DIFFICULTY_HEAT_SPIKES, difficulty))
	warning_msg = get_desc()

func apply_params(params: Dictionary) -> void:
	heat_spike_amount = float(params.get("heat_spike_amount", heat_spike_amount))
	warning_msg = get_desc()

func get_connection_flow_lines(_active_sig: ActiveSignal) -> Array[String]:
	return ["[b][color=red]TRIPWIRE[/color][/b]: Shutdown monitor armed."]

func postprocess_action(action_context: ActionContext) -> void:
	if action_context == null or not action_context.was_successful():
		return
	if action_context.action_type != ActionContext.ActionType.DISABLE_SIGNAL:
		return
	# Only the player's own shutdowns trip it, not system/IC side effects.
	if not _is_player_action(action_context):
		return
	var active_sig := action_context.primary_target
	if active_sig == null or active_sig.data == null:
		return
	action_context.append_log("[b][color=red]TRIPWIRE[/color][/b]: Shutdown flagged. Alarm raised.")
	_queue_heat(active_sig, heat_spike_amount, &"tripwire", "[TRIPWIRE] " + active_sig.data.system_id)
