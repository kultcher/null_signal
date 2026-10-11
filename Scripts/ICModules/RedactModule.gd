class_name RedactModule extends DisruptionModule

@export_range(0.0, 1.0, 0.01) var letter_fraction := 0.28

func get_effect_id() -> StringName:
	return &"redact"

func get_desc() -> String:
	return "Redact(%d%%)" % roundi(letter_fraction * 100.0)

func get_tuning_keys() -> Array[String]:
	return ["letter_fraction"]

func apply_difficulty(difficulty: int) -> void:
	letter_fraction = float(_pick_difficulty_value([0.18, 0.28, 0.38, 0.48, 0.58], difficulty))
	warning_msg = get_desc()

func get_connection_flow_lines(_sig: ActiveSignal) -> Array[String]:
	return ["[color=orange]REDACT[/color]: Individual letters in security prompts have been censored."]
