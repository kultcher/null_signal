extends Node

var failures := 0
var solves := 0

func check(label: String, condition: bool) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures += 1

func _ready() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var config := FuzzPuzzleConfig.new()
	var state := FuzzPuzzleState.new()
	state.reset(config, 0)
	check("defaults match packet budget and target", state.ammo == 5 and config.max_ammo == 5 and config.target_points == 100 and config.flight_time_sec == 0.5)
	check("full arc scores 20 including its edges", state.points_for_angle(deg_to_rad(-15)) == 20 and state.points_for_angle(deg_to_rad(15)) == 20)
	check("smooth falloff begins outside arc", is_equal_approx(state.points_for_angle(deg_to_rad(20)), 18) and is_equal_approx(state.points_for_angle(deg_to_rad(17.5)), 19))
	check("angular distance wraps across zero", is_equal_approx(state.points_for_angle(deg_to_rad(355)), 20))
	check("points clamp at zero on distant hits", is_zero_approx(state.points_for_angle(deg_to_rad(65))) and is_zero_approx(state.points_for_angle(PI)))
	for i in 5:
		check("packet %d fires" % i, state.fire(0))
	check("cannot fire with empty ammo", not state.fire(0) and state.ammo == 0)
	check("no immediate damage before impact", state.advance(0.49).is_empty() and state.progress == 0)
	check("five direct impacts solve exactly once at 0.5s", state.advance(0.01).size() == 5 and state.progress == 100 and state.solved and not state.fire(0) and state.advance(1).is_empty())
	state.reset(config, 0)
	state.fire(PI)
	state.advance(0.99)
	check("regen waits a whole second", state.ammo == 4)
	state.advance(0.01)
	check("one packet regenerates per second", state.ammo == 5)
	state.advance(100)
	state.fire(PI)
	state.advance(0.5)
	check("regen never banks credit above cap", state.ammo == 4)
	state.progress = 35
	state.advance(5)
	check("default progress has no decay", state.progress == 35)
	config.decay_points_per_second = 4
	state.reset(config, 0)
	state.progress = 10
	state.advance(1)
	check("optional decay is points per second", state.progress == 6)
	state.advance(5)
	check("decay clamps at zero", state.progress == 0)
	state.reset(config, 0)
	state.fire(0)
	state.advance(1)
	check("slow frames decay only after the impact earns points", state.progress == 18)
	check("feedback holds peak for 2.5s", config.impact_color(20, 2.5).is_equal_approx(config.direct_color))
	check("feedback fades halfway then reaches white", config.impact_color(20, 3.75).is_equal_approx(config.direct_color.lerp(Color.WHITE, 0.5)) and config.impact_color(20, 5).is_equal_approx(Color.WHITE))
	check("feedback gradient passes orange and yellow", config.impact_color(10, 0).is_equal_approx(config.medium_color) and config.impact_color(0, 0).is_equal_approx(config.weak_color))
	var hard := FuzzPuzzleConfig.new()
	hard.target_points = 160
	hard.decay_points_per_second = 3
	config.higher_difficulty_profiles.append(hard)
	var component := PuzzleComponent.new()
	component.puzzle_type = PuzzleComponent.Type.FUZZ
	component.puzzle_config = config
	component.set_difficulty(1)
	component.ensure_initial_lock_state()
	component.apply_escalation(1)
	check("difficulty and escalation select authored profiles", component.get_fuzz_config().target_points == 160 and component.get_fuzz_config().decay_points_per_second == 3)
	component.set_custom_fixed()
	component.apply_escalation(7)
	check("custom fixed difficulty ignores escalation", component.difficulty == 2)
	var definition := RunDefinition.new()
	var custom := definition.build_custom_puzzle(&"fuzz", {"config": hard})
	check("builder duplicates custom configuration", custom.get_fuzz_config().target_points == 160 and not custom.uses_escalation_difficulty and custom.puzzle_config != hard)

	var lab = load("res://Scenes/Tests/fuzz_test.tscn").instantiate()
	add_child(lab)
	await get_tree().process_frame
	var puzzle: FuzzPuzzle = lab.puzzle
	puzzle.set_process(false)
	puzzle.reset_puzzle(FuzzPuzzleConfig.new(), 0)
	puzzle.puzzle_solved.connect(func(): solves += 1)
	var input := InputEventMouseMotion.new()
	input.position = puzzle.arena.size * 0.5 + Vector2(0, 90)
	lab.get_node("Layout/Play/Unfocus").grab_focus()
	var previous := puzzle.aim_angle
	puzzle.arena_input(input)
	check("unfocused cannon cannot aim or fire", puzzle.aim_angle == previous and not puzzle.fire_packet())
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = puzzle.arena.size * 0.5 + Vector2(100, 0)
	puzzle.arena_input(click)
	check("activation click focuses without consuming ammo", puzzle.has_puzzle_focus() and puzzle.state.ammo == 5)
	puzzle.arena_input(input)
	check("focused motion steers cannon", is_equal_approx(puzzle.aim_angle, PI * 0.5))
	puzzle.aim_angle = 0
	puzzle.fire_packet()
	lab.get_node("Layout/Play/Unfocus").grab_focus()
	puzzle._process(0.5)
	check("packets in flight still score after losing focus", puzzle.state.progress == 20)
	puzzle._process(0.5)
	check("regen continues without focus", puzzle.state.ammo == 5)
	puzzle.grab_focus()
	for i in 4:
		puzzle.fire_packet()
	puzzle._process(0.5)
	puzzle._process(1)
	check("window emits one solve event", solves == 1 and puzzle.state.solved)
	if "--capture-fuzz" in OS.get_cmdline_user_args():
		lab.angle.value = 0
		lab.reveal.button_pressed = true
		lab.apply_and_restart()
		await get_tree().process_frame
		for angle in [0, 20, 40, 65]:
			puzzle.aim_angle = deg_to_rad(angle)
			puzzle.fire_packet()
		puzzle._process(0.5)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/fuzz-lab.png")
	lab.queue_free()
	await get_tree().process_frame

	# Exercise the existing RUN FUZZ -> WindowManager -> puzzle solve flow.
	var run_main = load("res://Scenes/run_main.tscn").instantiate()
	run_main.get_node("RunManager").level_script_path = "res://Resources/RunData/AuthoredRuns/NightAuditRun.gd"
	add_child(run_main)
	await get_tree().process_frame
	var sm = run_main.get_node("SignalTimeline/SignalManager")
	var sig: ActiveSignal = sm.get_signal_by_system_id("plate_cam")
	sig.data.puzzle = definition.make_fuzz_puzzle()
	sig.data.ic_modules = null
	run_main.get_node("SignalTimeline/TimelineManager").cells_per_second = 0
	CommandDispatch.terminal_window.switch_session(sig, false)
	CommandDispatch.process_command("RUN FUZZ", sig)
	await get_tree().process_frame
	var manager = run_main.get_node("WindowManager")
	var windows: Array = manager._active_puzzle_windows.keys()
	check("RUN FUZZ opens the Fuzz scene rather than Sniff", windows.size() == 1 and windows[0] is FuzzPuzzle)
	if not windows.is_empty():
		var live: FuzzPuzzle = windows[0]
		live.reset_puzzle(FuzzPuzzleConfig.new(), 0)
		live.grab_focus()
		live.aim_angle = 0
		for i in 5:
			live.fire_packet()
		live._process(0.5)
		check("solve unlocks linked signal and unregisters window", not sig.data.puzzle.is_locked() and manager._active_puzzle_windows.is_empty() and live.is_queued_for_deletion())
	run_main.queue_free()
	await get_tree().process_frame
	print("FUZZ TEST: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
