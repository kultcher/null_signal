# HeartbeatModule.gd
# A watchdog pulse on a fixed, visible rhythm. If the signal is down when a
# beat lands, the network flags the tamper (small heat) and restores it.
# Unlike Reboot, the window depends on *when* you kill it: right after a beat
# gives you the whole interval, right before one gives you almost nothing.

class_name HeartbeatModule extends ICModule

@export var beat_interval_sec: float = 7.0
@export var tamper_heat: float = 200.0
@export var _effect_scene: PackedScene = preload("res://Scenes/ic_progress_radial.tscn")

var timer: Timer = null
var effect_node: ICProgressRadial = null
var _host: WeakRef = null

const DIFFICULTY_BEAT_INTERVALS := [9.0, 7.0, 6.0, 5.0]
const DIFFICULTY_TAMPER_HEAT := [150.0, 200.0, 300.0, 400.0]

func get_desc():
	return "Heartbeat(%.0fs)" % beat_interval_sec

func get_codex_id():
	return &"codex_heartbeat"

func apply_difficulty(difficulty: int) -> void:
	beat_interval_sec = float(_pick_difficulty_value(DIFFICULTY_BEAT_INTERVALS, difficulty))
	tamper_heat = float(_pick_difficulty_value(DIFFICULTY_TAMPER_HEAT, difficulty))
	warning_msg = get_desc()
	_restart_if_running()

func apply_params(params: Dictionary) -> void:
	beat_interval_sec = maxf(1.0, float(params.get("beat_interval_sec", beat_interval_sec)))
	tamper_heat = float(params.get("tamper_heat", tamper_heat))
	warning_msg = get_desc()
	_restart_if_running()

func on_initialized(active_sig: ActiveSignal) -> void:
	_host = weakref(active_sig)

func on_visuals_ready(active_sig: ActiveSignal, ic_effects: ICEffectsHost, module_index: int) -> void:
	_host = weakref(active_sig)
	var effect_instance := _effect_scene.instantiate() as ICProgressRadial
	if effect_instance != null:
		effect_node = ic_effects.register_effect(
			&"heartbeat",
			effect_instance,
			module_index,
			ICEffectsHost.RevealMode.ON_SCAN,
			&"progress"
		) as ICProgressRadial
		if effect_node != null:
			effect_node.configure(active_sig, beat_interval_sec)
			effect_node.set_idle_visible(true)
	# The rhythm starts once the signal is on the feed, so the player sees
	# every beat from the first one.
	_start_beats()

func on_visuals_cleared(_active_sig: ActiveSignal) -> void:
	effect_node = null
	_stop_beats()

func get_connection_flow_lines(_active_sig: ActiveSignal) -> Array[String]:
	return [
		"[b][color=red]HEARTBEAT[/color][/b]: Watchdog link active.",
		"PULSE INTERVAL: %.1fs" % beat_interval_sec
	]

func _start_beats() -> void:
	if timer != null and is_instance_valid(timer):
		return
	timer = Timer.new()
	timer.one_shot = false
	timer.wait_time = beat_interval_sec
	GlobalEvents.add_child(timer)
	timer.timeout.connect(_on_beat)
	timer.start()
	if effect_node != null:
		effect_node.start(beat_interval_sec, timer)

func _stop_beats() -> void:
	if timer != null and is_instance_valid(timer):
		timer.queue_free()
	timer = null

func _restart_if_running() -> void:
	if timer == null or not is_instance_valid(timer):
		return
	_stop_beats()
	_start_beats()

func _on_beat() -> void:
	if effect_node != null:
		effect_node.start(beat_interval_sec, timer)
	var active_sig: ActiveSignal = _host.get_ref() if _host != null else null
	if active_sig == null or active_sig.data == null or not active_sig.is_disabled:
		return
	_notify("[b][color=red]HEARTBEAT[/color][/b]: %s missed a pulse. Watchdog restoring node." % active_sig.data.system_id)
	_queue_heat(active_sig, tamper_heat, &"heartbeat", "[HEARTBEAT] " + active_sig.data.system_id)
	var action := ActionContext.create_system_action(
		ActionContext.ActionType.ENABLE_SIGNAL,
		active_sig,
		ActionContext.SourceType.IC_MODULE
	)
	action.add_tag(&"ic")
	action.add_tag(&"heartbeat")
	action.set_metadata(&"codex_id", get_codex_id())
	ActionResolver.enqueue_action(action)
