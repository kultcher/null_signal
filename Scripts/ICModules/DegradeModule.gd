class_name DegradeModule extends DisruptionModule

@export_range(0.1, 120.0, 0.1) var ramp_sec := 16.0
@export_range(0.0, 1.0, 0.01) var max_corruption := 0.2
@export_range(0.05, 2.0, 0.05) var noise_interval_sec := 0.3

func get_effect_id() -> StringName:
	return &"degrade"

func get_desc() -> String:
	return "Degrade(%d%% / %.1fs)" % [roundi(max_corruption * 100.0), ramp_sec]

func get_tuning_keys() -> Array[String]:
	return ["ramp_sec", "max_corruption", "noise_interval_sec"]

func apply_difficulty(difficulty: int) -> void:
	ramp_sec = float(_pick_difficulty_value([20.0, 16.0, 12.0, 8.0, 5.0], difficulty))
	max_corruption = float(_pick_difficulty_value([0.12, 0.2, 0.3, 0.42, 0.55], difficulty))
	warning_msg = get_desc()

func get_connection_flow_lines(_sig: ActiveSignal) -> Array[String]:
	return ["[color=orange]DEGRADE[/color]: Channel integrity decays. Reconnect to restore."]
