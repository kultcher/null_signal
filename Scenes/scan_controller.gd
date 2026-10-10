extends Node2D

@onready var signal_manager = $"../SignalManager"

var active_scanning_signals: Array[ActiveSignal] = []
var queued_scanning_signals: Array[ActiveSignal] = []
var _scan_runtime_metadata: Dictionary = {}
var _is_processing_queue: bool = false

func _ready() -> void:
	if RAMManager != null and not RAMManager.ram_usage_changed.is_connected(_on_ram_usage_changed):
		RAMManager.ram_usage_changed.connect(_on_ram_usage_changed)
	_refresh_scan_queue_labels()

func _process(delta):
	if active_scanning_signals.is_empty():
		return
	for sig in active_scanning_signals.duplicate():
		_process_active_scan(sig, delta)

func toggle_scan(target_signal: ActiveSignal) -> void:
	if not GlobalEvents.is_tutorial_feature_enabled("scan"):
		return
	if target_signal == null:
		return
	if _is_scan_active(target_signal):
		cancel_scan(target_signal)
		return
	if _is_scan_queued(target_signal):
		_dequeue_scan(target_signal)
		return
	if target_signal.current_scan_index >= target_signal.scan_layers.size():
		return
	if RAMManager == null or RAMManager.get_available_ram() <= 0:
		_handle_scan_no_ram_available(target_signal)
		return
	_attempt_start_scan(target_signal)

func toggle_lock(clicked_signal: ActiveSignal) -> void:
	if not GlobalEvents.is_tutorial_feature_enabled("scan"):
		return
	handle_lock_toggle(clicked_signal)

func notify_signal_despawned(active_sig: ActiveSignal) -> void:
	if active_sig == null:
		return
	if _is_scan_active(active_sig):
		cancel_scan(active_sig)
	if _is_scan_queued(active_sig):
		_dequeue_scan(active_sig)

func start_signal_scan(target_signal: ActiveSignal) -> bool:
	if target_signal == null or target_signal.instance_node == null:
		return false
	if signal_manager != null and not signal_manager.is_signal_within_interaction_range(target_signal):
		return false
	if target_signal.current_scan_index >= target_signal.scan_layers.size():
		return false

	if _is_scan_active(target_signal):
		return false
	_dequeue_scan(target_signal)
	active_scanning_signals.append(target_signal)
	target_signal.is_being_scanned = true
	GlobalEvents.telemetry_event.emit(target_signal, "scan_started", {"layer_index": target_signal.current_scan_index, "layer": target_signal.scan_layers[target_signal.current_scan_index].name})

	target_signal.instance_node.bring_to_front()
	target_signal.instance_node.show_scanning_tooltip()
	return true

func handle_lock_toggle(clicked_signal: ActiveSignal):
	if clicked_signal == null:
		return
	if signal_manager != null and not signal_manager.is_signal_within_interaction_range(clicked_signal):
		return

	clicked_signal.is_tooltip_collapsed = not clicked_signal.is_tooltip_collapsed
	if clicked_signal.instance_node != null:
		clicked_signal.instance_node.tooltip_main.set_tooltip_collapsed(clicked_signal.is_tooltip_collapsed)
		clicked_signal.instance_node.bring_to_front()

func cancel_scan(active_sig: ActiveSignal = null):
	if active_sig == null or not _is_scan_active(active_sig):
		return

	active_scanning_signals.erase(active_sig)
	GlobalEvents.telemetry_event.emit(active_sig, "scan_cancelled", {})
	active_sig.current_layer_progress = 0
	if active_sig.instance_node != null:
		active_sig.instance_node.scan_cleanup()

	_release_scan_ram(active_sig)
	_clear_scan_runtime_metadata(active_sig)
	_cleanup_scan_visuals(active_sig)

func _process_active_scan(sig: ActiveSignal, delta: float):
	if sig == null:
		return

	if sig.instance_node == null:
		_release_scan_ram(sig)
		_cleanup_scan_visuals(sig)
		active_scanning_signals.erase(sig)
		return

	if sig.current_scan_index >= sig.scan_layers.size():
		_finish_completed_scan(sig)
		return

	var current_layer = sig.scan_layers[sig.current_scan_index]
	sig.current_layer_progress += delta
	var current_duration = current_layer.duration * _get_scan_time_multiplier(sig)

	sig.instance_node.update_scan_progress(sig.current_layer_progress, current_duration)

	if sig.current_layer_progress >= current_duration:
		_complete_scan_layer(sig, current_layer)

func _complete_scan_layer(sig: ActiveSignal, layer):
	layer.revealed = true
	sig.current_layer_progress = 0.0
	sig.current_scan_index += 1

	if sig.instance_node != null:
		sig.instance_node.append_tooltip(layer.description)
		sig.instance_node.update_scan_progress(0, 1.0)
		sig.instance_node.refresh_status_panels()

	GlobalEvents.signal_scanned.emit(sig.data, sig.current_scan_index)

	if sig.current_scan_index >= sig.scan_layers.size():
		if sig.instance_node != null:
			sig.instance_node.show_scan_complete()
		GlobalEvents.signal_scan_complete.emit(sig.data)
		_finish_completed_scan(sig)

func _cleanup_scan_visuals(sig: ActiveSignal):
	sig.is_being_scanned = false
	if sig.instance_node != null:
		sig.instance_node.refresh_scan_status()
		if sig.instance_node.has_method("sync_tooltip_body_visibility"):
			sig.instance_node.sync_tooltip_body_visibility()

func _finish_completed_scan(sig: ActiveSignal) -> void:
	if sig == null:
		return
	active_scanning_signals.erase(sig)
	_release_scan_ram(sig)
	_clear_scan_runtime_metadata(sig)
	if sig.instance_node != null:
		sig.instance_node.scan_cleanup()
	_cleanup_scan_visuals(sig)

func _is_scan_active(target_signal: ActiveSignal) -> bool:
	return target_signal != null and active_scanning_signals.has(target_signal)

func _is_scan_queued(target_signal: ActiveSignal) -> bool:
	return target_signal != null and queued_scanning_signals.has(target_signal)

func _get_scan_ram_reservation_id(target_signal: ActiveSignal) -> StringName:
	if target_signal == null or target_signal.data == null:
		return StringName()
	return StringName("scan_%s" % target_signal.data.system_id)

func _try_reserve_scan_ram(target_signal: ActiveSignal) -> bool:
	var reservation_id := _get_scan_ram_reservation_id(target_signal)
	if reservation_id == StringName() or RAMManager == null:
		return false
	return RAMManager.reserve_ram(reservation_id, 1)

func _release_scan_ram(target_signal: ActiveSignal) -> void:
	var reservation_id := _get_scan_ram_reservation_id(target_signal)
	if reservation_id == StringName() or RAMManager == null:
		return
	RAMManager.release_ram(reservation_id)

func _handle_scan_no_ram_available(target_signal: ActiveSignal) -> void:
	if target_signal == null or _is_scan_active(target_signal) or _is_scan_queued(target_signal):
		return
	queued_scanning_signals.append(target_signal)
	_refresh_scan_queue_labels()

func sync_signal_queue_visuals() -> void:
	_refresh_scan_queue_labels()

func _dequeue_scan(target_signal: ActiveSignal) -> void:
	if target_signal == null or not _is_scan_queued(target_signal):
		return
	queued_scanning_signals.erase(target_signal)
	_refresh_scan_queue_labels()

func _try_start_queued_scans() -> void:
	if RAMManager == null or _is_processing_queue:
		return

	_is_processing_queue = true
	var queue_changed := false
	while not queued_scanning_signals.is_empty() and RAMManager.get_available_ram() > 0:
		var next_signal: ActiveSignal = queued_scanning_signals[0]
		if not _can_start_queued_signal(next_signal):
			queued_scanning_signals.remove_at(0)
			queue_changed = true
			continue
		queued_scanning_signals.remove_at(0)
		queue_changed = true
		_attempt_start_scan(next_signal)

	if queue_changed:
		_refresh_scan_queue_labels()
	_is_processing_queue = false

func _can_start_queued_signal(target_signal: ActiveSignal) -> bool:
	if target_signal == null:
		return false
	if _is_scan_active(target_signal):
		return false
	if target_signal.current_scan_index >= target_signal.scan_layers.size():
		return false
	if target_signal.instance_node == null:
		return false
	if signal_manager != null and not signal_manager.is_signal_within_interaction_range(target_signal):
		return false
	return true

func _attempt_start_scan(target_signal: ActiveSignal) -> void:
	var action_context := ActionResolver.build_scan_action(target_signal)
	ActionResolver.resolve_action(action_context)
	if action_context == null or action_context.was_unsuccessful():
		return
	if not _try_reserve_scan_ram(target_signal):
		_handle_scan_no_ram_available(target_signal)
		return
	_store_scan_runtime_metadata(target_signal, action_context)
	if not start_signal_scan(target_signal):
		_release_scan_ram(target_signal)
		_clear_scan_runtime_metadata(target_signal)

func _store_scan_runtime_metadata(target_signal: ActiveSignal, action_context: ActionContext) -> void:
	var reservation_id := _get_scan_ram_reservation_id(target_signal)
	if reservation_id == StringName() or action_context == null:
		return
	_scan_runtime_metadata[reservation_id] = {
		"scan_time_multiplier": float(action_context.get_metadata(&"scan_time_multiplier", 1.0))
	}

func _clear_scan_runtime_metadata(target_signal: ActiveSignal) -> void:
	var reservation_id := _get_scan_ram_reservation_id(target_signal)
	if reservation_id == StringName():
		return
	_scan_runtime_metadata.erase(reservation_id)

func _get_scan_time_multiplier(target_signal: ActiveSignal) -> float:
	var reservation_id := _get_scan_ram_reservation_id(target_signal)
	if reservation_id == StringName() or not _scan_runtime_metadata.has(reservation_id):
		return 1.0
	var metadata = _scan_runtime_metadata[reservation_id]
	if metadata is Dictionary:
		return maxf(0.01, float(metadata.get("scan_time_multiplier", 1.0)))
	return 1.0

func _refresh_scan_queue_labels() -> void:
	if signal_manager != null and signal_manager.signal_queue != null:
		for sig in signal_manager.signal_queue:
			if sig != null and sig.instance_node != null:
				sig.instance_node.clear_scan_queue_position()
	for i in range(queued_scanning_signals.size()):
		var queued_signal: ActiveSignal = queued_scanning_signals[i]
		if queued_signal == null or queued_signal.instance_node == null:
			continue
		queued_signal.instance_node.set_scan_queue_position(i + 1)

func _on_ram_usage_changed(_used_ram: int, _total_ram: int) -> void:
	_try_start_queued_scans()
