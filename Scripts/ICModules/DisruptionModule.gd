class_name DisruptionModule extends ICModule
## Presentation IC live for the lifetime of an open terminal session, including
## background tabs. The terminal owns the runtime state; resources only tune it.

func get_effect_id() -> StringName:
	return &"disruption"

func get_codex_id() -> StringName:
	return StringName("codex_" + String(get_effect_id()))

func get_tuning_keys() -> Array[String]:
	return []

func apply_params(params: Dictionary) -> void:
	for key in get_tuning_keys():
		if params.has(key):
			set(key, params[key])
	warning_msg = get_desc()

func on_connect(active_sig: ActiveSignal) -> void:
	var terminal = CommandDispatch.terminal_window
	if terminal != null and terminal.get("disruptions") != null:
		terminal.disruptions.open_session(active_sig)

func on_session_closed(active_sig: ActiveSignal) -> void:
	_stop(active_sig)

func on_disabled(active_sig: ActiveSignal) -> void:
	_stop(active_sig)

func on_enabled(active_sig: ActiveSignal) -> void:
	if active_sig.terminal_session != null and active_sig.terminal_session.has_tab:
		on_connect(active_sig)

func _stop(active_sig: ActiveSignal) -> void:
	var terminal = CommandDispatch.terminal_window
	if terminal != null and terminal.get("disruptions") != null:
		terminal.disruptions.close_session(active_sig)
