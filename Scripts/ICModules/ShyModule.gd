# ShyModule.gd
# A few seconds after a full scan, the signal scrubs what you learned: scan
# data, lock state and IC readouts go back to unknown. Act while it's fresh,
# remember it, or spend time and RAM scanning again.

class_name ShyModule extends ICModule

@export var hide_delay_sec: float = 6.0
@export var _effect_scene: PackedScene = preload("res://Scenes/ic_progress_radial.tscn")

var timer: Timer = null
var effect_node: ICProgressRadial = null
var _host: WeakRef = null

const DIFFICULTY_HIDE_DELAYS := [8.0, 6.0, 5.0, 4.0]

func get_desc():
	return "Shy(%.0fs)" % hide_delay_sec

func get_codex_id():
	return &"codex_shy"

func apply_difficulty(difficulty: int) -> void:
	hide_delay_sec = float(_pick_difficulty_value(DIFFICULTY_HIDE_DELAYS, difficulty))
	warning_msg = get_desc()

func apply_params(params: Dictionary) -> void:
	hide_delay_sec = maxf(0.5, float(params.get("hide_delay_sec", hide_delay_sec)))
	warning_msg = get_desc()

func on_initialized(active_sig: ActiveSignal) -> void:
	_host = weakref(active_sig)

# Scans can only happen while the signal is on screen, so the scan listener
# lives as long as the signal's visuals. That also drops it when the run is
# torn down (signal_entity._exit_tree clears visuals), so modules from old
# runs don't keep reacting to new scans.
func on_visuals_ready(active_sig: ActiveSignal, ic_effects: ICEffectsHost, module_index: int) -> void:
	_host = weakref(active_sig)
	if not GlobalEvents.signal_scan_complete.is_connected(_on_signal_scan_complete):
		GlobalEvents.signal_scan_complete.connect(_on_signal_scan_complete)
	var effect_instance := _effect_scene.instantiate() as ICProgressRadial
	if effect_instance == null:
		return
	effect_node = ic_effects.register_effect(
		&"shy",
		effect_instance,
		module_index,
		ICEffectsHost.RevealMode.ON_SCAN,
		&"progress"
	) as ICProgressRadial
	if effect_node != null:
		effect_node.configure(active_sig, hide_delay_sec)
		effect_node.set_idle_visible(false)
		effect_node.set_gradient("res://Visuals/Gradients/orange_gradient_tex.tres")

func on_visuals_cleared(_active_sig: ActiveSignal) -> void:
	effect_node = null
	if GlobalEvents.signal_scan_complete.is_connected(_on_signal_scan_complete):
		GlobalEvents.signal_scan_complete.disconnect(_on_signal_scan_complete)

func get_connection_flow_lines(_active_sig: ActiveSignal) -> Array[String]:
	return ["[b][color=red]SHY[/color][/b]: Telemetry scrubbing scheduled after inspection."]

func _on_signal_scan_complete(signal_data: SignalData) -> void:
	var active_sig: ActiveSignal = _host.get_ref() if _host != null else null
	if active_sig == null or signal_data != active_sig.data:
		return
	if timer != null and is_instance_valid(timer):
		timer.queue_free()
	timer = Timer.new()
	timer.one_shot = true
	GlobalEvents.add_child(timer)
	timer.timeout.connect(_scrub, CONNECT_ONE_SHOT)
	timer.start(hide_delay_sec)
	if effect_node != null:
		effect_node.start(hide_delay_sec, timer)

func _scrub() -> void:
	if timer != null and is_instance_valid(timer):
		timer.queue_free()
	timer = null
	if effect_node != null:
		effect_node.stop()
	var active_sig: ActiveSignal = _host.get_ref() if _host != null else null
	if active_sig == null:
		return
	active_sig.reset_scan_progress()
	if active_sig.instance_node != null:
		active_sig.instance_node.rebuild_tooltip()
