class_name EscalationManager extends Node

const PIP_READY := Color(0.28, 0.12, 0.12, 1.0)
const PIP_TRIGGERED := Color(0.78, 0.24, 0.18, 1.0)
const PIP_ACTIVE := Color(1.0, 0.0, 0.22, 1.0)
const ESCALATION_SIGNAL_SPACING := 72.0

@export var escalation_thresholds: Array[float] = [0.25, 0.5, 0.75, 1.0]

@onready var heat_manager = $"../HeatManager"
@onready var run_manager = $"../RunManager"
@onready var timeline_manager = $"../SignalTimeline/TimelineManager"
@onready var scan_controller = $"../SignalTimeline/ScanController"
@onready var terminal_window = $"../WorkspaceAnchor/TerminalWindow"

@onready var escalation_panel: PanelContainer = $"../SignalTimeline/EscalationPanel"
@onready var escalation_pips: Array[Node] = $"../SignalTimeline/EscalationPanel/EscalationContainer/PipVbox".get_children()
@onready var escalation_anchor: Node2D = $"../SignalTimeline/EscalationAnchor"

var _signal_scene := preload("res://Scenes/signal_entity.tscn")
var _spawner := SignalSpawner.new()

var _triggered_tiers: Array[bool] = []
var _active_tier_index := -1

var _active_escalation_signals: Dictionary = {}

func _ready() -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED: return
	_initialize_tier_state()
	if GlobalEvents.heat_state_changed != null:
		GlobalEvents.heat_state_changed.connect(_on_heat_state_changed)
	if GlobalEvents.escalation_signal_disabled != null:
		GlobalEvents.escalation_signal_disabled.connect(_on_escalation_signal_disabled)
	if timeline_manager != null and timeline_manager.layout_changed != null:
		timeline_manager.layout_changed.connect(_on_timeline_layout_changed)

	_refresh_anchor_layout()
	_refresh_panel()

func get_active_tier_index() -> int:
	return _active_tier_index

func get_signal_by_system_id(system_id: String) -> ActiveSignal:
	for active_sig in _active_escalation_signals.values():
		if active_sig == null or active_sig.data == null:
			continue
		if active_sig.data.system_id == system_id:
			return active_sig
	return null

func get_triggered_tier_count() -> int:
	var count := 0
	for triggered in _triggered_tiers:
		if triggered:
			count += 1
	return count

func has_triggered_tier(tier_index: int) -> bool:
	if tier_index < 0 or tier_index >= _triggered_tiers.size():
		return false
	return _triggered_tiers[tier_index]

func _initialize_tier_state() -> void:
	_triggered_tiers.clear()
	for _i in escalation_thresholds.size():
		_triggered_tiers.append(false)

func _on_heat_state_changed(amount: float, _last_source: String) -> void:
	if not _is_escalation_enabled():
		return
	var heat_ratio := 0.0
	if heat_manager != null:
		heat_ratio = heat_manager.get_heat_ratio()
	else:
		var max_heat := 1.0
		if amount > 0.0:
			max_heat = amount
		heat_ratio = amount / max_heat

	_update_thresholds(heat_ratio)
	_refresh_panel()

func _is_escalation_enabled() -> bool:
	if run_manager == null or run_manager.current_run == null:
		return true
	return run_manager.current_run.is_escalation_enabled()

func _update_thresholds(heat_ratio: float) -> void:
	var new_active_tier := -1
	for i in range(escalation_thresholds.size()):
		var threshold := escalation_thresholds[i]
		if heat_ratio >= threshold:
			new_active_tier = i
			if not _triggered_tiers[i]:
				_triggered_tiers[i] = true
				_spawn_escalation_signal_for_tier(i)
				GlobalEvents.escalation_threshold_triggered.emit(i, threshold)

	if new_active_tier != _active_tier_index:
		_active_tier_index = new_active_tier
		GlobalEvents.escalation_state_changed.emit(_active_tier_index, get_triggered_tier_count())

func _on_timeline_layout_changed(_viewport_size: Vector2) -> void:
	_refresh_anchor_layout()
	_refresh_signal_layout()

func _refresh_anchor_layout() -> void:
	if escalation_panel == null or escalation_anchor == null:
		return
	if timeline_manager != null:
		# Sit just under the timeline strip / facility map.
		escalation_panel.position.y = timeline_manager.get_timeline_height() + 5.0
	escalation_anchor.position = escalation_panel.get_rect().get_center()

func _refresh_panel() -> void:
	for i in range(escalation_pips.size()):
		var pip := escalation_pips[i]
		if pip == null:
			continue
		if i == _active_tier_index:
			pip.self_modulate = PIP_ACTIVE
		elif _triggered_tiers[i]:
			pip.self_modulate = PIP_TRIGGERED
		else:
			pip.self_modulate = PIP_READY


func _spawn_escalation_signal_for_tier(tier_index: int) -> void:
	if _active_escalation_signals.has(tier_index):
		return

	var tier_id := "%02d" % [tier_index + 1]
	var active_sig := ActiveSignal.new()
	active_sig.data = _spawner.create_escalation_signal(tier_id, 2)
	active_sig.start_cell_index = 0.0
	active_sig.setup()
	active_sig.generate_scan_layers()
	_active_escalation_signals[tier_index] = active_sig

	var signal_node = _signal_scene.instantiate()
	escalation_anchor.add_child(signal_node)
	signal_node.setup(active_sig)
	signal_node.signal_interaction.connect(_on_escalation_signal_left_clicked)
	signal_node.scan_toggle_requested.connect(_on_escalation_signal_right_clicked)
	signal_node.tooltip_lock_requested.connect(_on_escalation_signal_middle_clicked)
	signal_node.hover_started.connect(_on_escalation_signal_mouse_enter)
	signal_node.hover_ended.connect(_on_escalation_signal_mouse_exit)
	signal_node.tree_exited.connect(_on_escalation_signal_tree_exited.bind(tier_index), CONNECT_ONE_SHOT)
	active_sig.instance_node = signal_node

	_refresh_signal_layout()

func _on_escalation_signal_tree_exited(tier_index: int) -> void:
	_active_escalation_signals.erase(tier_index)
	_refresh_signal_layout()

func _on_escalation_signal_disabled(active_sig: ActiveSignal) -> void:
	if active_sig == null:
		return

	var tier_index := -1
	for key in _active_escalation_signals.keys():
		if _active_escalation_signals[key] == active_sig:
			tier_index = int(key)
			break

	if tier_index == -1:
		return

	if terminal_window != null:
		terminal_window.hide_tab_for_signal(active_sig)

	_remove_disabled_escalation_signal_later(active_sig, tier_index)

func _remove_disabled_escalation_signal_later(active_sig: ActiveSignal, tier_index: int) -> void:
	if not _active_escalation_signals.has(tier_index):
		return
	if _active_escalation_signals[tier_index] != active_sig:
		return

	if active_sig.instance_node != null:
		var signal_node := active_sig.instance_node
		signal_node.modulate.a = 1.0
		var fade_tween := signal_node.create_tween()
		fade_tween.tween_property(signal_node, "modulate:a", 0.0, 3.0)
		await fade_tween.finished

		if not _active_escalation_signals.has(tier_index):
			return
		if _active_escalation_signals[tier_index] != active_sig:
			return
		if active_sig.instance_node != signal_node:
			return

		signal_node.queue_free()
		return

	_active_escalation_signals.erase(tier_index)
	_refresh_signal_layout()

func _refresh_signal_layout() -> void:
	var sorted_tiers: Array[int] = []
	for tier_index in _active_escalation_signals.keys():
		var active_sig: ActiveSignal = _active_escalation_signals[tier_index]
		if active_sig == null or active_sig.instance_node == null:
			continue
		sorted_tiers.append(int(tier_index))

	sorted_tiers.sort()

	var count := sorted_tiers.size()
	if count <= 0:
		return

	var center_offset := float(count - 1) * 0.5
	for i in range(count):
		var active_sig: ActiveSignal = _active_escalation_signals[sorted_tiers[i]]
		var signal_node := active_sig.instance_node
		if signal_node == null:
			continue
		signal_node.position = Vector2((float(i) - center_offset) * ESCALATION_SIGNAL_SPACING, 0.0)

func _is_escalation_signal_in_range(_active_sig: ActiveSignal) -> bool:
	return true

func _on_escalation_signal_left_clicked(active_sig: ActiveSignal) -> void:
	if not GlobalEvents.is_tutorial_feature_enabled("connect"):
		return
	if terminal_window == null:
		return
	terminal_window.access_signal_via_click(active_sig)

func _on_escalation_signal_right_clicked(active_sig: ActiveSignal) -> void:
	if not GlobalEvents.is_tutorial_feature_enabled("scan"):
		return
	if not _is_escalation_signal_in_range(active_sig):
		return
	if scan_controller != null:
		scan_controller.toggle_scan(active_sig)

func _on_escalation_signal_middle_clicked(active_sig: ActiveSignal) -> void:
	if not GlobalEvents.is_tutorial_feature_enabled("scan"):
		return
	if not _is_escalation_signal_in_range(active_sig):
		return
	if active_sig == null:
		return
	active_sig.is_tooltip_collapsed = not active_sig.is_tooltip_collapsed
	if active_sig.instance_node != null:
		active_sig.instance_node.tooltip_main.set_tooltip_collapsed(active_sig.is_tooltip_collapsed)
		active_sig.instance_node.bring_to_front()

func _on_escalation_signal_mouse_enter(active_sig: ActiveSignal) -> void:
	if not GlobalEvents.is_tutorial_feature_enabled("scan"):
		return
	if not _is_escalation_signal_in_range(active_sig):
		return
	if active_sig != null and active_sig.instance_node != null:
		active_sig.instance_node.set_hover_highlight(true)
		active_sig.instance_node.show_hover_tooltip()

func _on_escalation_signal_mouse_exit(active_sig: ActiveSignal) -> void:
	if active_sig != null and active_sig.instance_node != null:
		active_sig.instance_node.set_hover_highlight(false)
		active_sig.instance_node.fade_tooltip_body()
