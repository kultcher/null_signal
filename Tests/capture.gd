extends Node

var cells: Array = []
var out_dir := "user://shots/"
var prefix := "map"
var frames_between := 20
var stage := ""
var shots := 6
var actions: Dictionary = {}  # shot index -> command string typed into terminal

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("cells="):
			for c in a.substr(6).split(","):
				cells.append(float(c))
		elif a.begins_with("prefix="):
			prefix = a.substr(7)
		elif a.begins_with("frames="):
			frames_between = int(a.substr(7))
		elif a.begins_with("stage="):
			stage = a.substr(6)
		elif a.begins_with("shots="):
			shots = int(a.substr(6))
	var run_main: Node = load("res://Scenes/run_main.tscn").instantiate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("level="): run_main.get_node("RunManager").level_script_path = a.substr(6)
	var tm_node := run_main.get_node("TutorialManager")
	if stage == "":
		tm_node.set_script(null)
	else:
		tm_node.debug_skip_to_stage = stage
	add_child(run_main)
	await get_tree().process_frame
	var timeline = run_main.get_node("SignalTimeline/TimelineManager")
	if stage == "":
		timeline.BASE_CELLS_PER_SECOND = 0.0
		timeline.cells_per_second = 0.0
		for c in cells:
			if c >= 1000.0:
				# Progress-based capture: 1000 + progress along the route.
				timeline.path_progress = c - 1000.0
				timeline._apply_path_progress()
				for i in frames_between:
					await get_tree().process_frame
				_save("%s_p%05.1f" % [prefix, c - 1000.0])
				continue
			timeline.set_runner_cell(c)
			for i in frames_between:
				await get_tree().process_frame
			_save("%s_%05.1f" % [prefix, c])
	else:
		for s in shots:
			for i in frames_between:
				await get_tree().process_frame
			_save("%s_%02d_c%05.1f" % [prefix, s, timeline.current_cell_pos])
	get_tree().quit()

func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + name + ".png")
