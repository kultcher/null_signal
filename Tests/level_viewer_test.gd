extends Node

var failures := 0
var run_main: Node
var viewer
var timeline
var sm

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run_main = load("res://Scenes/run_main.tscn").instantiate()
	run_main.process_mode = Node.PROCESS_MODE_PAUSABLE
	run_main.get_node("RunManager").level_script_path = "res://Resources/RunData/AuthoredRuns/NightAuditRun.gd"
	run_main.get_node("TutorialManager").set_script(null)
	add_child(run_main)
	await _frames(3)
	viewer = run_main.get_node("LevelViewer")
	timeline = run_main.get_node("SignalTimeline/TimelineManager")
	sm = run_main.get_node("SignalTimeline/SignalManager")
	_key(KEY_F2)
	await _frames(3)
	check("F2 opens and pauses gameplay", viewer.panel.visible and get_tree().paused)
	check("Night Audit has five sections and twenty-one signals", viewer.facility_layout.sections.size() == 5 and viewer.entries.size() == 21)
	check("distance overlay defaults on", viewer.distance_toggle.button_pressed)
	var progress: float = timeline.path_progress
	var cell: float = timeline.current_cell_pos
	var count: int = sm.signal_queue.size()
	var queue_snapshot: Array = sm.signal_queue.duplicate()
	var patrol_snapshot: Array[float] = []
	for sig in sm.signal_queue:
		patrol_snapshot.append(sig.runtime_cell_x)
	var heat: float = run_main.get_node("HeatManager").current_heat
	viewer.pan_pixels(Vector2(180.0, -240.0))
	var anchor := Vector2(380.0, 340.0)
	var before: Vector2 = viewer.screen_to_map(anchor)
	var length: float = viewer.facility_layout.get_total_length()
	viewer.zoom_at(anchor, 1.7)
	check("zoom remains anchored at cursor", before.distance_to(viewer.screen_to_map(anchor)) < 0.0001)
	check("zoom does not change route distance", is_equal_approx(length, viewer.facility_layout.get_total_length()))
	var resolved := false
	for entry in viewer.entries:
		if entry["data"].system_id == "guard_b2":
			resolved = is_equal_approx(entry["data"].mobility.patrol_points[1].cell_x, 4.5)
	check("patrol offsets resolve to absolute cells", resolved)
	viewer.measure_at(Vector2(1.0, 2.0))
	viewer.measure_at(Vector2(4.0, 6.0))
	check("ruler reports authored cells and lanes", viewer.measurement_text().contains("dx 3.00 cells | dy 4.00 lanes"))
	for section in range(5):
		viewer._select_section(section + 1)
		var rect: Rect2 = viewer.get_map_rect()
		for room in viewer.facility_layout.get_rooms_in_section(viewer.get_current_section()):
			var a: Vector2 = viewer.cell_lane_to_screen(room.start_cell, room.lane_top)
			var b: Vector2 = viewer.cell_lane_to_screen(room.end_cell, room.lane_bottom)
			check("fit %s includes %s" % [viewer.get_current_section().id, room.id], rect.has_point(a) and rect.has_point(b))
		await _frames(2)
	viewer.fit_level()
	check("whole-level mode reveals all authored signals", viewer.map_layer.preview_signals.size() == 21)
	await _frames(6)
	check("preview navigation preserves live runner and signals", is_equal_approx(progress, timeline.path_progress) and is_equal_approx(cell, timeline.current_cell_pos) and sm.signal_queue.size() == count and sm.signal_queue == queue_snapshot)
	var patrols_frozen := true
	for i in sm.signal_queue.size():
		patrols_frozen = patrols_frozen and is_equal_approx(patrol_snapshot[i], sm.signal_queue[i].runtime_cell_x)
	check("patrol positions freeze with gameplay", patrols_frozen)
	check("heat freezes with gameplay", is_equal_approx(heat, run_main.get_node("HeatManager").current_heat))
	# Inspect exact placement and resolved detection data.
	viewer._select_section(1)
	var entry: Dictionary = viewer.entries[0]
	viewer.select_at(viewer.cell_lane_to_screen(entry["cell"], entry["data"].lane))
	check("click selects signal and exposes exact cell", viewer.selected_index == 0 and viewer.inspector.text.contains("Cell: 1.20"))
	viewer.measurement.clear()
	viewer.measure_screen_point(viewer.cell_lane_to_screen(1.2, 0.0) + Vector2(3.0, 2.0))
	check("ruler snaps to exact signal placement", viewer.measurement[0] == Vector2(1.2, 0.0))
	viewer.measurement.clear()
	var original_layout = viewer.facility_layout
	check("missing file retains snapshot", not viewer.load_preview("user://no_such_level.gd") and viewer.facility_layout == original_layout)
	# A real file edit: reload must rebuild both layout and duplicated signal data.
	var temp_path := "user://level_viewer_reload_test.gd"
	_write_fixture(temp_path, 2.0)
	check("load authored fixture", viewer.load_preview(temp_path))
	viewer.selected_index = 0
	viewer.center = Vector2(3.4, 1.7)
	viewer.zoom = 0.7
	_write_fixture(temp_path, 5.0)
	viewer.reload_preview()
	check("reload reads edited file and preserves selection/view", is_equal_approx(viewer.entries[0]["cell"], 5.0) and viewer.selected_index == 0 and viewer.center == Vector2(3.4, 1.7) and is_equal_approx(viewer.zoom, 0.7))
	check("preview reload never replaces the live run", run_main.get_node("RunManager").get_run_id() == "night_audit" and sm.signal_queue == queue_snapshot)
	if "--invalid-reload" in OS.get_cmdline_user_args():
		var valid_layout = viewer.facility_layout
		var bad_file := FileAccess.open(temp_path, FileAccess.WRITE)
		bad_file.store_string("extends RunDefinition\nfunc BROKEN(\n")
		bad_file.close()
		check("parse error retains valid preview", not viewer.load_preview(temp_path) and viewer.facility_layout == valid_layout and viewer.selected_index == 0)
		bad_file = FileAccess.open(temp_path, FileAccess.WRITE)
		bad_file.store_string("extends RefCounted\n")
		bad_file.close()
		check("unrelated script rejected before instantiation", not viewer.load_preview(temp_path) and viewer.facility_layout == valid_layout)
	for filename in DirAccess.get_files_at("res://Resources/RunData/AuthoredRuns"):
		if filename.ends_with(".gd"):
			check("preview loads " + filename, viewer.load_preview("res://Resources/RunData/AuthoredRuns/" + filename))
			viewer.fit_level()
			await _frames(2)
	viewer.load_preview("res://Resources/RunData/AuthoredRuns/NightAuditRun.gd")
	viewer._select_section(1)
	viewer.select_at(viewer.cell_lane_to_screen(9.0, 3.0))
	await _frames(3)
	if DisplayServer.get_name() != "headless" and not OS.get_environment("NULL_VIEWER_SHOT_DIR").is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("NULL_VIEWER_SHOT_DIR") + "/null-viewer-parking.png")
	viewer._select_section(2)
	viewer.select_at(viewer.cell_lane_to_screen(34.0, 0.0))
	await _frames(3)
	if DisplayServer.get_name() != "headless" and not OS.get_environment("NULL_VIEWER_SHOT_DIR").is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("NULL_VIEWER_SHOT_DIR") + "/null-viewer-office.png")
	_key(KEY_F2)
	await _frames(2)
	check("F2 returns to unpaused gameplay", not viewer.panel.visible and not get_tree().paused)
	check("runner advances after closing", timeline.path_progress > progress)
	get_tree().paused = true
	_key(KEY_F2)
	await _frames(2)
	_key(KEY_ESCAPE)
	await _frames(2)
	check("existing pause is restored on exit", get_tree().paused and not viewer.panel.visible)
	get_tree().paused = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	print("LEVEL VIEWER: %d failures" % failures)
	run_main.queue_free()
	await _frames(2)
	get_tree().quit(1 if failures > 0 else 0)

func _write_fixture(path: String, cell: float) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('extends "res://Resources/RunData/RunDefinition.gd"\nfunc get_spawns() -> Array[Dictionary]:\n\treturn [spawn(BASIC_CAMERA, %s).id("reload_cam").lane(2).build()]\n' % cell)

func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.keycode = key
	event.pressed = false
	Input.parse_input_event(event)

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
