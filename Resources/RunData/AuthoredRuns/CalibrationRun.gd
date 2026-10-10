extends RunDefinition

func get_run_id() -> String:
	return "gauntlet"

func get_display_name() -> String:
	return "Calibration corridor"

func is_escalation_enabled() -> bool:
	return false

# Signals are supplied one at a time by the gauntlet controller.
