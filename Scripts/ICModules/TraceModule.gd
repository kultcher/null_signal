class_name TraceModule extends ICModule

@export var trace_time: float = 12.0
@export var heat_spike_amount: float = 1000.0
@export var _effect_scene: PackedScene = preload("res://Scenes/ic_progress_radial.tscn")

var timer: Timer = null
var effect_node: ICProgressRadial = null
var _warning_timers: Array[Timer] = []

const DIFFICULTY_TRACE_TIMES := [12.0, 10.0, 8.0, 7.0, 6.0]

func get_desc():
	return "Trace(%.1fs)" % trace_time

func get_codex_id():
	return &"codex_trace"

func on_visuals_ready(active_sig: ActiveSignal, ic_effects: ICEffectsHost, module_index: int) -> void:
	var effect_instance := _effect_scene.instantiate() as ICProgressRadial
	if effect_instance == null:
		return
	effect_node = ic_effects.register_effect(
		&"trace",
		effect_instance,
		module_index,
		ICEffectsHost.RevealMode.ON_SCAN,
		&"progress"
	) as ICProgressRadial
	if effect_node != null:
		effect_node.configure(active_sig, trace_time)
		effect_node.set_idle_visible(false)
		effect_node.set_gradient("res://Visuals/Gradients/red_gradient_tex.tres")

func apply_difficulty(difficulty: int) -> void:
	trace_time = float(_pick_difficulty_value(DIFFICULTY_TRACE_TIMES, difficulty))
	if effect_node != null:
		effect_node.configure(null, trace_time)

func apply_params(params: Dictionary) -> void:
	trace_time = float(params.get("trace_time", trace_time))
	heat_spike_amount = float(params.get("heat_spike_amount", heat_spike_amount))
	if effect_node != null:
		effect_node.configure(null, trace_time)

func on_connect(active_sig: ActiveSignal):
	if active_sig == null:
		return
	_start_trace(active_sig)

func on_session_closed(_active_sig: ActiveSignal):
	_clear_trace()

func on_disabled(_active_sig: ActiveSignal):
	_clear_trace()

func get_connection_flow_lines(_active_sig: ActiveSignal) -> Array[String]:
	return [
		"[b][color=red]TRACE[/color][/b]: Counter-intrusion trace armed.",
		"TRACE WINDOW: %.1fs" % trace_time
	]

func _start_trace(active_sig: ActiveSignal) -> void:
	_clear_trace()
	timer = Timer.new()
	timer.one_shot = true
	GlobalEvents.add_child(timer)
	timer.timeout.connect(_on_trace_timeout.bind(active_sig), CONNECT_ONE_SHOT)
	timer.start(trace_time)
	if effect_node != null:
		effect_node.start(trace_time, timer)
	_schedule_warning_timers(active_sig)

func _schedule_warning_timers(active_sig: ActiveSignal) -> void:
	var halfway_delay := trace_time * 0.5
	_add_warning_timer(halfway_delay, func(): _emit_trace_transient(
		active_sig,
		"[b][color=orange]TRACE[/color][/b]: Signal attribution closing in."
	))
	for seconds_left in [3, 2, 1]:
		var seconds_value := int(seconds_left)
		var warning_delay := trace_time - float(seconds_value)
		if warning_delay <= 0.0:
			continue
		_add_warning_timer(warning_delay, func(): _emit_trace_transient(
			active_sig,
			"[b][color=red]TRACE[/color][/b]: Heat spike in %d..." % seconds_value
		))

func _add_warning_timer(delay_sec: float, callback: Callable) -> void:
	var warning_timer := Timer.new()
	warning_timer.one_shot = true
	GlobalEvents.add_child(warning_timer)
	warning_timer.timeout.connect(callback, CONNECT_ONE_SHOT)
	warning_timer.start(delay_sec)
	_warning_timers.append(warning_timer)

func _emit_trace_transient(active_sig: ActiveSignal, message: String) -> void:
	if CommandDispatch.terminal_window == null:
		return
	CommandDispatch.terminal_window.print_transient(message)

func _on_trace_timeout(active_sig: ActiveSignal) -> void:
	_clear_trace()
	if active_sig == null or active_sig.terminal_session == null:
		return
	var action := ActionContext.create_system_action(
		ActionContext.ActionType.ADD_HEAT,
		active_sig,
		ActionContext.SourceType.IC_MODULE
	)
	action.heat_delta = heat_spike_amount
	action.add_tag(&"ic")
	action.add_tag(&"trace")
	action.set_metadata(&"codex_id", get_codex_id())
	action.set_metadata(&"heat_source", "[TRACE] " + active_sig.data.system_id)
	ActionResolver.enqueue_action(action)
	_emit_trace_transient(
		active_sig,
		"[b][color=red]TRACE[/color][/b]: Trace completed. Heat spike registered."
	)

func _clear_trace() -> void:
	if timer != null and is_instance_valid(timer):
		timer.queue_free()
	timer = null
	for warning_timer in _warning_timers:
		if warning_timer != null and is_instance_valid(warning_timer):
			warning_timer.queue_free()
	_warning_timers.clear()
	if effect_node != null:
		effect_node.stop()
