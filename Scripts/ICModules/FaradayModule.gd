class_name FaradayModule extends ICModule

@export var max_runner_distance_cells: float = 2.0
@export var _effect_scene: PackedScene = preload("res://Scenes/faraday_overlay.tscn")
@export var _shield_shader: Shader = preload("res://Shaders/ic_faraday_shield.gdshader")

var effect_node: FaradayEffect = null

const DIFFICULTY_RUNNER_DISTANCES := [1.5, 2.0, 3.0, 4.0]




func get_desc():
	return "Faraday(%.1fc)" % max_runner_distance_cells

func get_codex_id():
	return &"codex_faraday"

func on_visuals_ready(active_sig: ActiveSignal, ic_effects: ICEffectsHost, module_index: int) -> void:
	var effect_instance := _effect_scene.instantiate() as FaradayEffect
	if effect_instance == null:
		return
	effect_node = ic_effects.register_effect(
		&"faraday",
		effect_instance,
		module_index,
		ICEffectsHost.RevealMode.ON_SCAN,
		&"overlay"
	) as FaradayEffect
	if effect_node != null:
		effect_node.configure_faraday(active_sig, max_runner_distance_cells, _shield_shader)

func apply_difficulty(difficulty: int) -> void:
	max_runner_distance_cells = float(_pick_difficulty_value(DIFFICULTY_RUNNER_DISTANCES, difficulty))
	if effect_node != null:
		effect_node.max_runner_distance_cells = max_runner_distance_cells

func apply_params(params: Dictionary) -> void:
	max_runner_distance_cells = float(params.get("max_runner_distance_cells", max_runner_distance_cells))
	if effect_node != null:
		effect_node.max_runner_distance_cells = max_runner_distance_cells

func process_action(action_context: ActionContext) -> void:
	if action_context == null or action_context.primary_target == null:
		return
	if action_context.source_type != ActionContext.SourceType.TERMINAL_COMMAND:
		return
	if action_context.action_type == ActionContext.ActionType.ACCESS_SIGNAL:
		return
	if action_context.action_type == ActionContext.ActionType.START_SCAN_SIGNAL:
		return
	if CommandDispatch.signal_manager == null:
		return

	var runner_distance = CommandDispatch.signal_manager.get_horizontal_runner_distance_cells(action_context.primary_target)
	if runner_distance <= max_runner_distance_cells:
		return

	if not action_context.blocked_by.has(&"faraday"):
		action_context.blocked_by.append(&"faraday")
	action_context.fail(
		"COMMAND BLOCKED. [b][color=orange]FARADAY[/color][/b] shielding active. Move within %.1f cells to establish a stable link." % max_runner_distance_cells
	)
