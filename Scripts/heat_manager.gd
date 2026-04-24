extends Node

@export var max_heat: float = 5000.0

@onready var timeline_manager = $"../SignalTimeline/TimelineManager"

var current_heat: float = 0.0
var last_source: String = ""
var null_spike_count: float = 0.0

func _ready() -> void:
	GlobalEvents.heat_increased.connect(_on_heat_increased)
	GlobalEvents.heat_set_requested.connect(_on_heat_set_requested)
	set_process(true)
	_emit_heat_state_changed()

func _process(delta: float) -> void:
	if timeline_manager == null or not timeline_manager.null_spike_active:
		return

	null_spike_count += delta * 2.0
	if null_spike_count > 25.0:
		add_heat(0.25, "Null Spike t4")
	if null_spike_count > 20.0:
		add_heat(0.175, "Null Spike t3")
	if null_spike_count > 15.0:
		add_heat(0.125, "Null Spike t2")
	if null_spike_count > 10.0:
		add_heat(0.1, "Null Spike t1")

func add_heat(amount: float, source: String = "") -> void:
	if is_zero_approx(amount):
		return
	set_heat(current_heat + amount, source)

func set_heat(amount: float, source: String = "") -> void:
	current_heat = clampf(amount, 0.0, max_heat)
	if not source.is_empty():
		last_source = source
	_emit_heat_state_changed()

func clear_heat(amount: float, source: String = "") -> void:
	if is_zero_approx(amount):
		return
	set_heat(current_heat - amount, source)

func get_heat() -> float:
	return current_heat

func get_heat_ratio() -> float:
	if max_heat <= 0.0:
		return 0.0
	return current_heat / max_heat

func get_max_heat() -> float:
	return max_heat

func _on_heat_increased(amount: float, source: String) -> void:
	add_heat(amount, source)

func _on_heat_set_requested(amount: float) -> void:
	set_heat(amount)

func _emit_heat_state_changed() -> void:
	GlobalEvents.heat_state_changed.emit(current_heat, last_source)
