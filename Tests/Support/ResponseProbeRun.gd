extends RunDefinition

# One obstacle on the runner's lane, chosen by the NULL_RESPONSE_PROBE
# environment variable. Used by Tests/response_outcome_test.gd.

func get_run_id() -> String:
	return "response_probe"

func is_escalation_enabled() -> bool:
	return false

func get_spawns() -> Array[Dictionary]:
	match OS.get_environment("NULL_RESPONSE_PROBE"):
		"door": return [spawn(BASIC_DOOR, 3.0).id("probe").lane(2).add_puzzle("sniff", 1).build()]
		"guard": return [spawn(BASIC_GUARD, 3.0).id("probe").lane(2).build()]
		"combat_drone": return [spawn(COMBAT_DRONE, 3.0).id("probe").lane(2).build()]
		# Stationary guard out of reveal range of the runner at the start.
		"far_guard": return [spawn(BASIC_GUARD, 6.5).id("probe").lane(0).build()]
	return []
