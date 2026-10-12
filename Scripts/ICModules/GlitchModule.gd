class_name GlitchModule extends DisruptionModule
## Passive: the signal jumps between its real position and decoys whenever it
## is live, connected or not (SessionDisruptionController tracks it).

@export_range(2, 12, 1) var position_count := 3
@export_range(0.1, 10.0, 0.05) var jump_interval_sec := 1.4
@export var max_offset_px := Vector2(150, 60)

func get_effect_id() -> StringName:
	return &"glitch"

func get_desc() -> String:
	return "Glitch(%d / %.2fs)" % [position_count, jump_interval_sec]

func get_tuning_keys() -> Array[String]:
	return ["position_count", "jump_interval_sec", "max_offset_px"]

func apply_difficulty(difficulty: int) -> void:
	position_count = int(_pick_difficulty_value([2, 3, 4, 5, 6], difficulty))
	jump_interval_sec = float(_pick_difficulty_value([1.8, 1.4, 1.0, 0.7, 0.45], difficulty))
	warning_msg = get_desc()

func get_connection_flow_lines(_sig: ActiveSignal) -> Array[String]:
	return ["[color=orange]GLITCH[/color]: Unstable image. Decoy positions shimmer; the real signal holds steady."]
