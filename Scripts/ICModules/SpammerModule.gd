class_name SpammerModule extends DisruptionModule

enum Placement { TIMELINE, TERMINAL, BOTH }

@export var placement: Placement = Placement.BOTH
@export_range(0.1, 30.0, 0.1) var spawn_interval_sec := 3.0
@export_range(1, 20, 1) var max_popups := 2
@export var popup_size := Vector2(300, 150)

func get_effect_id() -> StringName:
	return &"spammer"

func get_desc() -> String:
	return "Spammer(%d / %.1fs)" % [max_popups, spawn_interval_sec]

func get_tuning_keys() -> Array[String]:
	return ["placement", "spawn_interval_sec", "max_popups", "popup_size"]

func apply_difficulty(difficulty: int) -> void:
	spawn_interval_sec = float(_pick_difficulty_value([4.0, 3.0, 2.0, 1.25, 0.8], difficulty))
	max_popups = int(_pick_difficulty_value([1, 2, 3, 4, 5], difficulty))
	warning_msg = get_desc()

func get_connection_flow_lines(_sig: ActiveSignal) -> Array[String]:
	return ["[color=orange]SPAMMER[/color]: Unsolicited channels attached. Disconnect to purge."]
