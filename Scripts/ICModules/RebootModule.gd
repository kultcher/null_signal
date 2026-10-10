class_name RebootModule extends ICModule

@export var reboot_time: float = 5.0
@export var _effect_scene: PackedScene = preload("res://Scenes/ic_progress_radial.tscn")

var timer: Timer
var effect_node: ICProgressRadial = null

const DIFFICULTY_REBOOT_TIMES := [3.0, 5.0, 10.0, 15.0]

func _init():
	warning_msg = get_desc()

func get_desc():
	var desc: String = "Reboot(%ds)" % reboot_time
	return desc

func get_codex_id():
	return &"codex_reboot"

func on_visuals_ready(active_sig: ActiveSignal, ic_effects: ICEffectsHost, module_index: int) -> void:
	var effect_instance := _effect_scene.instantiate() as ICProgressRadial
	if effect_instance == null:
		return
	effect_node = ic_effects.register_effect(
		&"reboot",
		effect_instance,
		module_index,
		ICEffectsHost.RevealMode.ON_SCAN,
		&"progress"
	) as ICProgressRadial
	if effect_node != null:
		effect_node.configure(active_sig, reboot_time)
		effect_node.set_gradient("res://Visuals/Gradients/cyan_gradient_tex.tres")
		# Signal re-entered the view mid-reboot: pick the countdown back up.
		if timer != null and is_instance_valid(timer) and not timer.is_stopped():
			effect_node.start(reboot_time, timer)

func on_visuals_cleared(_active_sig: ActiveSignal) -> void:
	effect_node = null

func apply_difficulty(difficulty: int) -> void:
	reboot_time = float(_pick_difficulty_value(DIFFICULTY_REBOOT_TIMES, difficulty))


func apply_params(params: Dictionary) -> void:
	reboot_time = float(params.get("reboot_time", reboot_time))

func postprocess_action(action_context: ActionContext) -> void:
	print("REBOOT POST PROC")
	if action_context == null or not action_context.was_successful():
		print("NOT SUCCESS")
		return
	if action_context.action_type != ActionContext.ActionType.DISABLE_SIGNAL:
		print("ACTION TYPE")
		return
	var active_sig := action_context.primary_target
	if active_sig == null:
		return

	if timer != null and is_instance_valid(timer):
		timer.queue_free()
	timer = Timer.new()
	timer.one_shot = true
	GlobalEvents.add_child(timer)
	timer.timeout.connect(_reboot.bind(active_sig), CONNECT_ONE_SHOT)
	timer.start(reboot_time)
	if effect_node != null:
		effect_node.start(reboot_time, timer)

func on_enabled(_active_sig: ActiveSignal):
	if timer != null and is_instance_valid(timer):
		timer.queue_free()
	timer = null
	if effect_node != null:
		effect_node.stop()
	
func _reboot(active_sig: ActiveSignal):
	if timer != null and is_instance_valid(timer):
		timer.queue_free()
		timer = null
	if effect_node != null:
		effect_node.stop()
	if active_sig == null or not active_sig.is_disabled:
		return

	var action := ActionContext.create_system_action(
		ActionContext.ActionType.ENABLE_SIGNAL,
		active_sig,
		ActionContext.SourceType.IC_MODULE
	)
	action.add_tag(&"ic")
	action.add_tag(&"reboot")
	action.set_metadata(&"codex_id", get_codex_id())
	ActionResolver.enqueue_action(action)
