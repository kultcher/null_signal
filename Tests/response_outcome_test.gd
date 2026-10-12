extends Node

# What each blocker does when the runner reaches it and nobody intervenes:
#   guard / combat drone: 1 damage, then the signal disables itself
#   locked door: no damage, a heat spike, then it opens
# Run: godot --headless --fixed-fps 60 res://Tests/response_outcome_test.tscn

const PROBE_RUN := "res://Tests/Support/ResponseProbeRun.gd"
const WAIT_SEC := 30.0

var failures := 0

func _ready() -> void:
	var guard := await _probe("guard")
	check("guard deals exactly 1 damage (got %s)" % str(guard["damage"]), guard["damage"] == [1.0])
	check("guard leaves the runner alive", guard["health"] == 2 and not guard["died"])
	check("guard disables after hitting", guard["disabled"])

	var drone := await _probe("combat_drone")
	check("combat drone deals exactly 1 damage (got %s)" % str(drone["damage"]), drone["damage"] == [1.0])
	check("combat drone disables after hitting", drone["disabled"])

	var door := await _probe("door")
	check("door deals no damage", door["damage"].is_empty() and door["health"] == 3)
	check("door spikes heat (got %.0f)" % door["heat"], door["heat"] >= 500.0)
	check("runner gets past the door", door["cell"] > 3.5)

	print("RESPONSE TEST: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures > 0 else 0)

func _probe(kind: String) -> Dictionary:
	OS.set_environment("NULL_RESPONSE_PROBE", kind)
	var run_main: Node = load("res://Scenes/run_main.tscn").instantiate()
	run_main.get_node("RunManager").level_script_path = PROBE_RUN
	run_main.get_node("TutorialManager").set_script(null)
	var result := {"damage": [], "died": false}
	var on_damage := func(amount: float): result["damage"].append(amount)
	var on_died := func(): result["died"] = true
	GlobalEvents.runners_damaged.connect(on_damage)
	GlobalEvents.runner_died.connect(on_died)
	add_child(run_main)
	await get_tree().create_timer(WAIT_SEC).timeout
	result["health"] = run_main.get_node("SignalTimeline/GridLayer/RunnerTeam/PanelContainer/RunnerHealth").current_health
	result["heat"] = run_main.get_node("HeatManager").current_heat
	result["cell"] = run_main.get_node("SignalTimeline/TimelineManager").current_cell_pos
	result["disabled"] = true
	for sig in run_main.get_node("SignalTimeline/SignalManager").signal_queue:
		if sig.data.system_id == "probe":
			result["disabled"] = sig.is_disabled
	GlobalEvents.runners_damaged.disconnect(on_damage)
	GlobalEvents.runner_died.disconnect(on_died)
	run_main.queue_free()
	Engine.time_scale = 1.0
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	return result

func check(name: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + name)
