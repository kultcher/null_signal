# TetherModule.gd
# While a session to this signal is open, you can't act on anything else:
# no connecting to or commanding other signals until it's dealt with (the
# signal goes down) or you disconnect. At higher tiers, disconnecting with
# the job unfinished costs heat. Scanning stays available, so you can still
# watch the feed; you just can't touch it.

class_name TetherModule extends ICModule

@export var abandon_heat: float = 0.0

const DIFFICULTY_ABANDON_HEAT := [0.0, 300.0, 500.0, 800.0]

func get_desc():
	if abandon_heat > 0.0:
		return "Tether(+%d)" % int(abandon_heat)
	return "Tether"

func get_codex_id():
	return &"codex_tether"

func apply_difficulty(difficulty: int) -> void:
	abandon_heat = float(_pick_difficulty_value(DIFFICULTY_ABANDON_HEAT, difficulty))
	warning_msg = get_desc()

func apply_params(params: Dictionary) -> void:
	abandon_heat = float(params.get("abandon_heat", abandon_heat))
	warning_msg = get_desc()

func get_connection_flow_lines(_active_sig: ActiveSignal) -> Array[String]:
	var lines: Array[String] = [
		"[b][color=red]TETHER[/color][/b]: Exclusive session lock engaged.",
		"Other links suspended until this node is closed out."
	]
	if abandon_heat > 0.0:
		lines.append("EARLY RELEASE PENALTY: +%d heat" % int(abandon_heat))
	return lines

func process_external_action(action_context: ActionContext, host_sig: ActiveSignal) -> void:
	if action_context == null or host_sig == null or host_sig.is_disabled:
		return
	if action_context.source_type != ActionContext.SourceType.TERMINAL_COMMAND:
		return
	if action_context.action_type == ActionContext.ActionType.SHOW_HELP:
		return
	var target := action_context.primary_target
	if target == null or target == host_sig:
		return
	action_context.block(
		&"tether",
		"[b][color=orange]TETHER[/color][/b]: Session locked to %s. Finish it or disconnect first." % host_sig.data.system_id
	)

func on_session_closed(active_sig: ActiveSignal):
	if active_sig == null or active_sig.data == null or active_sig.is_disabled:
		return
	if abandon_heat <= 0.0:
		return
	_notify("[b][color=red]TETHER[/color][/b]: Session abandoned. Release penalty applied.")
	_queue_heat(active_sig, abandon_heat, &"tether", "[TETHER] " + active_sig.data.system_id)
