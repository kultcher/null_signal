# SiphonModule.gd
# Heat bleeds every second a session to this signal stays open. No hard
# timer: you can take as long as you like, it just keeps costing more.

class_name SiphonModule extends ICModule

@export var heat_per_second: float = 60.0
@export var tick_sec: float = 1.0
@export var _effect_scene: PackedScene = preload("res://Scenes/ic_progress_radial.tscn")

var timer: Timer = null
var effect_node: ICProgressRadial = null
var _host: WeakRef = null

const DIFFICULTY_HEAT_PER_SECOND := [40.0, 60.0, 90.0, 130.0]

func get_desc():
	return "Siphon(%d/s)" % int(heat_per_second)

func get_codex_id():
	return &"codex_siphon"

func apply_difficulty(difficulty: int) -> void:
	heat_per_second = float(_pick_difficulty_value(DIFFICULTY_HEAT_PER_SECOND, difficulty))
	warning_msg = get_desc()

func apply_params(params: Dictionary) -> void:
	heat_per_second = float(params.get("heat_per_second", heat_per_second))
	tick_sec = maxf(0.1, float(params.get("tick_sec", tick_sec)))
	warning_msg = get_desc()

func on_visuals_ready(active_sig: ActiveSignal, ic_effects: ICEffectsHost, module_index: int) -> void:
	var effect_instance := _effect_scene.instantiate() as ICProgressRadial
	if effect_instance == null:
		return
	effect_node = ic_effects.register_effect(
		&"siphon",
		effect_instance,
		module_index,
		ICEffectsHost.RevealMode.ON_SCAN,
		&"progress"
	) as ICProgressRadial
	if effect_node != null:
		effect_node.configure(active_sig, tick_sec)
		effect_node.set_idle_visible(false)
		effect_node.set_gradient("res://Visuals/Gradients/red_gradient_tex.tres")
		if timer != null and is_instance_valid(timer):
			effect_node.start(tick_sec, timer)

func on_visuals_cleared(_active_sig: ActiveSignal) -> void:
	effect_node = null

func get_connection_flow_lines(_active_sig: ActiveSignal) -> Array[String]:
	return [
		"[b][color=red]SIPHON[/color][/b]: Session metering enabled.",
		"HEAT BLEED: %d/s while connected" % int(heat_per_second)
	]

func on_connect(active_sig: ActiveSignal):
	if active_sig == null or active_sig.is_disabled:
		return
	_host = weakref(active_sig)
	if timer != null and is_instance_valid(timer):
		return
	timer = Timer.new()
	timer.one_shot = false
	timer.wait_time = tick_sec
	GlobalEvents.add_child(timer)
	timer.timeout.connect(_on_tick)
	timer.start()
	if effect_node != null:
		effect_node.start(tick_sec, timer)

func on_session_closed(_active_sig: ActiveSignal):
	_stop()

func on_disabled(_active_sig: ActiveSignal):
	_stop()

func _on_tick() -> void:
	var active_sig: ActiveSignal = _host.get_ref() if _host != null else null
	if active_sig == null or active_sig.is_disabled or active_sig.terminal_session == null or not active_sig.terminal_session.has_tab:
		_stop()
		return
	_queue_heat(active_sig, heat_per_second * tick_sec, &"siphon", "[SIPHON] " + active_sig.data.system_id)
	if effect_node != null:
		effect_node.start(tick_sec, timer)

func _stop() -> void:
	if timer != null and is_instance_valid(timer):
		timer.queue_free()
	timer = null
	if effect_node != null:
		effect_node.stop()
