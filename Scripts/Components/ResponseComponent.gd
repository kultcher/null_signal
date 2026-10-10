# ResponseComponent.gd

class_name ResponseComponent extends Resource

@export var effects: Array[Resource] = []

enum Effect { HEAT, DAMAGE, STOP }
enum Cadence { ONESHOT, CONTINUOUS, DELAYED }

var _delay_in_progress: Dictionary = {}
var _delay_completed: Dictionary = {}
var _delay_hold_tokens: Dictionary = {}

func on_detection(active_sig: ActiveSignal, delta: float, delay: float = 0.0) -> void:
	if active_sig.is_disabled:
		return

	var sig_id := active_sig.get_instance_id()
	if delay > 0.0 and not _delay_completed.get(sig_id, false):
		if not _delay_in_progress.get(sig_id, false):
			_start_delay_window(active_sig, delay)
		return

	_apply_effects(active_sig, delta)

func _start_delay_window(active_sig: ActiveSignal, delay: float) -> void:
	var sig_id := active_sig.get_instance_id()
	_delay_in_progress[sig_id] = true
	GlobalEvents.telemetry_event.emit(active_sig, "breach_started", {"delay_sec": delay})
	_set_movement_disabled(active_sig, true)
	_set_detection_paused(active_sig, true)
	if not _delay_hold_tokens.has(sig_id):
		_delay_hold_tokens[sig_id] = GlobalEvents.acquire_runner_hold("response_delay")
	_finish_delay_window(active_sig, delay)

func _finish_delay_window(active_sig: ActiveSignal, delay: float) -> void:
	var sig_id := active_sig.get_instance_id()
	var elapsed := 0.0
	var check_step := 0.05

	while elapsed < delay:
		if not _delay_in_progress.get(sig_id, false):
			return
		if active_sig.is_disabled:
			_delay_in_progress.erase(sig_id)
			_set_movement_disabled(active_sig, false)
			_set_detection_paused(active_sig, false)
			_release_delay_hold(sig_id)
			return
		var remaining: float = delay - elapsed
		var wait_time: float = minf(check_step, remaining)
		await GlobalEvents.get_tree().create_timer(wait_time, false).timeout
		elapsed += wait_time

	# An OP during the final timer step can cancel this response too.
	if not _delay_in_progress.get(sig_id, false):
		return
	_delay_in_progress.erase(sig_id)
	_delay_completed[sig_id] = true

	if not active_sig.is_disabled:
		_apply_effects(active_sig, 0.0)
		if not active_sig.is_disabled:
			active_sig.disable_signal()
		if active_sig.data.type == SignalData.Type.DOOR and active_sig.data.door_locked:
			GlobalEvents.signal_breached.emit(active_sig)

	_set_movement_disabled(active_sig, false)
	_set_detection_paused(active_sig, false)
	_release_delay_hold(sig_id)

func _apply_effects(active_sig: ActiveSignal, delta: float) -> void:
	if active_sig.is_disabled:
		return

	var one_shot_effects: Array[Resource] = []
	for effect in effects:
		if effect == null:
			continue
		match effect.cadence:
			ResponseEffect.Cadence.CONTINUOUS:
				_apply_effect(effect, effect.amount * delta, active_sig)
			ResponseEffect.Cadence.ONESHOT:
				_apply_effect(effect, effect.amount, active_sig)
				one_shot_effects.append(effect)

	if one_shot_effects.is_empty():
		return

	for effect in one_shot_effects:
		effects.erase(effect)

	if effects.is_empty() and not active_sig.is_disabled:
		active_sig.disable_signal()


func _apply_effect(effect: ResponseEffect, value: float, _active_sig: ActiveSignal) -> void:
	match effect.effect_type:
		ResponseEffect.EffectType.HEAT:
			GlobalEvents.heat_increased.emit(value, "Detected by " + _active_sig.data.display_name + ".")
		ResponseEffect.EffectType.DAMAGE:
			GlobalEvents.runners_damaged.emit(value)


func get_desc():
	return "Blank"

func _set_movement_disabled(active_sig: ActiveSignal, disabled: bool) -> void:
	if active_sig == null or active_sig.data == null:
		return
	if active_sig.data.mobility == null:
		return
	active_sig.data.mobility.movement_disabled = disabled

func reset_delay_state(active_sig: ActiveSignal, resume_runners: bool = false) -> void:
	if active_sig == null:
		return

	var sig_id := active_sig.get_instance_id()
	_delay_in_progress.erase(sig_id)
	_delay_completed.erase(sig_id)
	_set_movement_disabled(active_sig, false)
	_set_detection_paused(active_sig, false)
	_release_delay_hold(sig_id)

func _release_delay_hold(sig_id: int) -> void:
	if not _delay_hold_tokens.has(sig_id):
		return
	var token: String = _delay_hold_tokens[sig_id]
	_delay_hold_tokens.erase(sig_id)
	GlobalEvents.release_runner_hold(token)

func _set_detection_paused(active_sig: ActiveSignal, paused: bool) -> void:
	if active_sig == null:
		return
	active_sig.runtime_detection_paused = paused
