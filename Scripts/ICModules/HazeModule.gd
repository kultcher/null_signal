class_name HazeModule extends ICModule

@export var scan_time_multiplier: float = 2.0
@export var _effect_scene: PackedScene = preload("res://Scenes/ic_overlay.tscn")
@export var _haze_shader: Shader = preload("res://Shaders/ic_haze_overlay_swirl.gdshader")

var HAZE_X_OFFSET: Vector2 = Vector2(25,0)
var effect_node: ICOverlay = null

const DIFFICULTY_SCAN_MULTIPLIERS := [2.0, 2.5, 3.0, 4.0]

func get_desc():
	return "Haze(x%.1f)" % scan_time_multiplier

func get_codex_id():
	return &"codex_haze"

func on_visuals_ready(active_sig: ActiveSignal, ic_effects: ICEffectsHost, module_index: int) -> void:
	var effect_instance := _effect_scene.instantiate() as ICOverlay
	if effect_instance == null:
		return
	effect_node = ic_effects.register_effect(
		&"haze",
		effect_instance,
		module_index,
		ICEffectsHost.RevealMode.ALWAYS,
		&"overlay"
	) as ICOverlay
	if effect_node != null:
		effect_node.configure(active_sig, _haze_shader)
		effect_node.set_active(true)
		effect_node.scale = Vector2(1.25, 1.25)
		effect_node.position -= HAZE_X_OFFSET

func apply_difficulty(difficulty: int) -> void:
	scan_time_multiplier = float(_pick_difficulty_value(DIFFICULTY_SCAN_MULTIPLIERS, difficulty))

func apply_params(params: Dictionary) -> void:
	scan_time_multiplier = float(params.get("scan_time_multiplier", scan_time_multiplier))

func process_action(action_context: ActionContext) -> void:
	if action_context == null or action_context.primary_target == null:
		return
	if action_context.action_type != ActionContext.ActionType.START_SCAN_SIGNAL:
		return

	var current_multiplier := float(action_context.get_metadata(&"scan_time_multiplier", 1.0))
	action_context.set_metadata(
		&"scan_time_multiplier",
		maxf(0.01, current_multiplier * scan_time_multiplier)
	)
	GlobalEvents.telemetry_event.emit(action_context.primary_target, "ic_triggered", {"ic": "haze", "difficulty": base_difficulty, "effect": "scan_slowed", "multiplier": scan_time_multiplier})
