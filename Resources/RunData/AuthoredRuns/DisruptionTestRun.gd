extends RunDefinition

func get_run_id() -> String:
	return "disruptive_ic_lab"

func get_display_name() -> String:
	return "Disruptive IC lab"

func is_escalation_enabled() -> bool:
	return false

func get_spawns() -> Array[Dictionary]:
	return []
