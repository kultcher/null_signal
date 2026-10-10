extends Node

var failures := 0
var run_main: Node
var viewer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run_main = load("res://Scenes/run_main.tscn").instantiate()
	run_main.get_node("RunManager").level_script_path = "res://Resources/RunData/AuthoredRuns/NightAuditRun.gd"
	get_tree().root.add_child.call_deferred(run_main)
	await _frames(3)
	get_tree().current_scene = run_main
	var timeline = run_main.get_node("SignalTimeline/TimelineManager")
	timeline.cells_per_second = 0.0
	var sm = run_main.get_node("SignalTimeline/SignalManager")
	var door: ActiveSignal = sm.get_signal_by_system_id("records_door")
	door.data.puzzle.puzzle_locked = false
	door.set_door_locked(false)
	sm.get_signal_by_system_id("plate_cam").disable_signal()
	run_main.get_node("HeatManager").set_heat(2300.0, "restart test")
	var old_escalation: ActiveSignal = run_main.get_node("EscalationManager")._active_escalation_signals.values()[0]
	var old_spawn_behavior = old_escalation.data.escalation.spawn_behavior
	var old_spawn_token: int = old_spawn_behavior._spawn_loop_token
	GlobalEvents.runners_damaged.emit(1.0)
	GlobalEvents.acquire_runner_hold("restart test")
	GlobalEvents.first_null_spike = true
	GlobalEvents.set_tutorial_feature_enabled("scan", false)
	RAMManager.reserve_ram(&"restart_test", 1)
	var program := ProgramManager.get_programs()[0]
	program.state = ProgramInstance.State.CLEANUP
	program.time_remaining_sec = 999.0
	viewer = run_main.get_node("LevelViewer")
	viewer.open_viewer()
	check("restart disabled until a point is chosen", viewer.restart_button.disabled and not viewer.restart_here())
	viewer._select_section(3)
	var preview_door: SignalData
	var vault: SignalData
	for entry in viewer.entries:
		if entry["data"].system_id == "records_door": preview_door = entry["data"]
		if entry["data"].system_id == "vault_cage": vault = entry["data"]
	check("preview shows initial puzzle lock, independent of live unlock", viewer.security_details(preview_door).contains("Puzzle: SNIFF\nStatus: Locked\nDifficulty: 1"))
	check("preview exposes IC description and difficulty", viewer.security_details(vault).contains("Tripwire(+600)") and viewer.security_details(vault).contains("Difficulty: 1 (scales with escalation)"))
	check("unprotected signals report no puzzle and no IC", viewer.security_details(viewer.entries[0]["data"]).contains("Puzzle: None\nIC: None"))
	# Same X occurs at multiple points along this vertical exit. The restart
	# must keep the segment and fraction, rather than just seek to its cell.
	viewer.choose_start_point(Vector2(54.9, -1.4))
	check("start point snaps to selected section's vertical route", viewer.start_location["section"] == 2 and viewer.start_position.distance_to(Vector2(54.6, -1.4)) < 0.0001)
	check("choosing a start enables restart without moving gameplay", not viewer.restart_button.disabled and timeline.current_cell_pos < 1.0)
	viewer.reload_preview()
	check("reload preserves selected start section and fraction", viewer.start_location["section_id"] == "records" and viewer.start_position.distance_to(Vector2(54.6, -1.4)) < 0.0001)
	if DisplayServer.get_name() != "headless" and not OS.get_environment("NULL_VIEWER_SHOT_DIR").is_empty():
		viewer.select_at(viewer.cell_lane_to_screen(48.5, 2.0))
		await _frames(2)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("NULL_VIEWER_SHOT_DIR") + "/null-viewer-security.png")
	var old_id := run_main.get_instance_id()
	check("restart request accepted", viewer.restart_here())
	await _wait_for_new_run(old_id)
	check("old scene is replaced and new scene is current", not is_instance_id_valid(old_id) and get_tree().current_scene == run_main)
	timeline = run_main.get_node("SignalTimeline/TimelineManager")
	sm = run_main.get_node("SignalTimeline/SignalManager")
	check("restart is playable and unpaused", not get_tree().paused and timeline.cells_per_second > 0.0 and is_equal_approx(Engine.time_scale, 1.0))
	get_tree().paused = true
	check("vertical position and section survive the scene bootstrap", timeline.current_section_index == 2 and Vector2(timeline.current_cell_pos, timeline.runner_lane_pos).distance_to(Vector2(54.6, -1.4)) < 0.15)
	check("fresh run resets heat and health", is_zero_approx(run_main.get_node("HeatManager").current_heat) and run_main.get_node("SignalTimeline/GridLayer/RunnerTeam/PanelContainer/RunnerHealth").current_health == 3)
	check("fresh run restores authored locks and enabled signals", sm.get_signal_by_system_id("records_door").data.puzzle.is_locked() and sm.get_signal_by_system_id("records_door").data.door_locked and not sm.get_signal_by_system_id("plate_cam").is_disabled)
	check("fresh run has only authored signal population", sm.signal_queue.size() == 21)
	check("old escalation spawn loop is canceled", old_escalation.is_disabled and not old_escalation.data.escalation.is_active() and old_spawn_behavior._spawn_loop_token > old_spawn_token)
	check("old IC timers are removed from autoload host", GlobalEvents.get_children().filter(func(node: Node) -> bool: return node is Timer).is_empty())
	check("autoload holds, tutorial gating, RAM and cooldowns reset", not GlobalEvents.has_runner_holds() and not GlobalEvents.first_null_spike and GlobalEvents.is_tutorial_feature_enabled("scan") and RAMManager.get_reserved_ram() == 0 and ProgramManager.get_programs()[0].state == ProgramInstance.State.DOCKED)
	check("new managers registered and terminal session fresh", CommandDispatch.signal_manager == sm and CommandDispatch.timeline_manager == timeline and CommandDispatch.terminal_window.active_signal == CommandDispatch.terminal_window.root_signal)
	viewer = run_main.get_node("LevelViewer")
	viewer.open_viewer()
	check("viewer reopens after restarting a freshly compiled script", viewer.preview_run != null and viewer.script_path.ends_with("NightAuditRun.gd") and viewer.entries.size() == 21)
	viewer.close_viewer()
	get_tree().paused = false
	var progress: float = timeline.path_progress
	await _frames(3)
	check("runner progresses from the selected point", timeline.path_progress > progress)
	get_tree().paused = true
	# Let the old scene's pending escalation delay expire. It must not
	# spawn a drone through the new run's CommandDispatch registration.
	await get_tree().create_timer(10.1).timeout
	check("delayed old-run work cannot spawn into the new run", sm.signal_queue.size() == 21 and is_zero_approx(run_main.get_node("HeatManager").current_heat))
	old_escalation = null
	old_spawn_behavior = null
	get_tree().paused = false
	# Select a different run and start it: the scene's default Night Audit
	# path must not override the run currently being previewed.
	viewer.open_viewer()
	viewer.load_preview("res://Resources/RunData/AuthoredRuns/TestRun.gd")
	viewer.fit_level()
	viewer.choose_start_point(Vector2(5.0, 2.0))
	old_id = run_main.get_instance_id()
	viewer.restart_here()
	await _wait_for_new_run(old_id)
	check("restart uses the selected preview run", run_main.get_node("RunManager").get_run_id() == "test")
	check("repeat restart leaves one run and no coordinator", get_tree().root.get_children().filter(func(node: Node) -> bool: return node.scene_file_path == "res://Scenes/run_main.tscn").size() == 1)
	viewer = run_main.get_node("LevelViewer")
	viewer.open_viewer()
	viewer.load_preview("res://Resources/RunData/AuthoredRuns/TutorialRun.gd")
	viewer.fit_level()
	viewer.choose_start_point(Vector2(30.0, 2.0))
	old_id = run_main.get_instance_id()
	viewer.restart_here()
	await _wait_for_new_run(old_id)
	await _frames(3)
	check("tutorial debug start bypasses intro and feature locks", run_main.get_node("RunManager").get_run_id() == "tutorial" and run_main.get_node("RunManager").debug_free_play and not GlobalEvents.has_runner_holds() and GlobalEvents.is_tutorial_feature_enabled("terminal_commands"))
	print("VIEWER RESTART: %d failures" % failures)
	run_main.queue_free()
	await _frames(2)
	get_tree().quit(1 if failures > 0 else 0)

func _wait_for_new_run(old_id: int) -> void:
	for i in 10:
		await get_tree().process_frame
		var current := get_tree().current_scene
		if current != null and current.get_instance_id() != old_id:
			run_main = current
			return
	check("restart completed within ten frames", false)

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failures += 1
