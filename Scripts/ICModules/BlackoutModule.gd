class_name BlackoutModule extends DisruptionModule

func get_effect_id() -> StringName:
	return &"blackout"

func get_desc() -> String:
	return "Blackout"

func get_connection_flow_lines(_sig: ActiveSignal) -> Array[String]:
	return ["[color=orange]BLACKOUT[/color]: Signal feed suppressed while this channel is open."]
