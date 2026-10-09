extends Node
func _ready() -> void:
	var lvl := "res://Resources/RunData/AuthoredRuns/ICTestRun.gd"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("level="):
			lvl = a.substr(6)
	var run_main: Node = load("res://Scenes/run_main.tscn").instantiate()
	run_main.get_node("RunManager").level_script_path = lvl
	var tm = run_main.get_node("TutorialManager")
	tm.set_script(null)
	add_child(run_main)
	await get_tree().process_frame
	var timeline = run_main.get_node("SignalTimeline/TimelineManager")
	timeline.set_runner_cell(5.0)
	var last: float = timeline.current_cell_pos
	var stalls := 0
	var frames := 120
	var deltas := []
	for i in frames:
		await get_tree().process_frame
		var x: float = timeline.current_cell_pos
		if is_equal_approx(x, last):
			stalls += 1
		deltas.append(snappedf((x - last) * timeline.cell_width_px, 0.01))
		last = x
	print("JITTER stalled_frames=", stalls, "/", frames, " px_steps=", deltas.slice(0, 20))
	get_tree().quit()
