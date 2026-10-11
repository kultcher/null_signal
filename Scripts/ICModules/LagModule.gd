class_name LagModule extends DisruptionModule

@export_range(0.0, 10.0, 0.05) var delay_sec := 0.3

func get_effect_id() -> StringName:
	return &"lag"

func get_desc() -> String:
	return "Lag(%.2fs)" % delay_sec

func get_tuning_keys() -> Array[String]:
	return ["delay_sec"]

func apply_difficulty(difficulty: int) -> void:
	delay_sec = float(_pick_difficulty_value([0.15, 0.3, 0.5, 0.75, 1.0], difficulty))
	warning_msg = get_desc()

func get_connection_flow_lines(_sig: ActiveSignal) -> Array[String]:
	return ["[color=orange]LAG[/color]: Input channel buffered by %.2fs." % delay_sec]
