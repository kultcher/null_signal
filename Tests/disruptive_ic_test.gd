extends Node

var game: Node
var terminal
var controller: SessionDisruptionController
var manager
var timeline
var submitted: Array = []
var failures := 0
var serial := 0

func _ready() -> void:
	game = load("res://Scenes/run_main.tscn").instantiate()
	game.get_node("RunManager").level_script_path = "res://Resources/RunData/AuthoredRuns/DisruptionTestRun.gd"
	game.get_node("RunManager").debug_free_play = true
	add_child(game)
	await get_tree().process_frame
	terminal = CommandDispatch.terminal_window
	controller = terminal.disruptions
	manager = CommandDispatch.signal_manager
	timeline = CommandDispatch.timeline_manager
	timeline.BASE_CELLS_PER_SECOND = 0.0
	timeline.cells_per_second = 0.0
	ActionResolver.debug_logging = false
	await get_tree().create_timer(1.0).timeout
	CommandDispatch.command_submitted.connect(func(text, sig): submitted.append([text, sig]))
	check("hardware reparent preserves root session", terminal.root_session.active_signal == terminal.root_signal)
	_test_factories()
	await _test_lag()
	await _test_degrade_and_redact()
	await _test_blackout_and_glitch()
	await _test_spammer()
	await _test_combination_and_reveal()
	await _test_lifetime()
	game.queue_free()
	await get_tree().process_frame
	check("run teardown clears terminal autoload reference", CommandDispatch.terminal_window == null)
	await _test_lab()
	print("DISRUPTIVE_IC failures=", failures)
	get_tree().quit(1 if failures else 0)

func check(label: String, condition: bool) -> void:
	print("DISRUPTIVE_IC ", "PASS " if condition else "FAIL ", label)
	if not condition:
		failures += 1

func _test_factories() -> void:
	var definition := RunDefinition.new()
	for key in ["lag", "spammer", "degrade", "blackout", "glitch", "redact"]:
		var module := definition.build_ic(key, 3) as DisruptionModule
		check(key + " factory, difficulty, codex", module != null and module.base_difficulty == 3 and ResourceLoader.exists("res://Resources/Codex/codex_" + key + ".tres"))
	var lag := definition.build_custom_ic("lag", {"delay_sec": 0.42}) as LagModule
	check("custom tuning bypasses escalation", is_equal_approx(lag.delay_sec, 0.42) and not lag.uses_escalation_difficulty)

func host(modules: Array[Resource]) -> ActiveSignal:
	serial += 1
	var data := RunDefinition.BASIC_DOOR.duplicate(true) as SignalData
	data.system_id = "disruption_%d" % serial
	data.display_name = data.system_id
	data.ic_modules = RunDefinition.new().make_ic(modules)
	data.set_meta("auto_codex_popups", false)
	data.puzzle = null
	manager.spawn_signal_data(data, 2.0 + float(serial) * 0.04)
	manager.update_signal_position()
	return manager.signal_queue[-1]

func connect_host(sig: ActiveSignal) -> void:
	terminal.switch_session(sig, false)
	terminal.command_line.grab_focus()
	terminal.command_line.edit()

func close(sig: ActiveSignal) -> void:
	if sig.terminal_session != null and sig.terminal_session.has_tab:
		terminal._close_session_tab(sig.terminal_session, sig)

func key(code: int, unicode_value: int = 0, control := false) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	event.physical_keycode = code
	event.unicode = unicode_value
	event.ctrl_pressed = control
	get_viewport().push_input(event, true)

func type_text(text: String) -> void:
	for character in text:
		key(character.to_upper().unicode_at(0), character.unicode_at(0))

func _test_lag() -> void:
	var lag := LagModule.new()
	lag.delay_sec = 0.12
	var sig := host([lag])
	connect_host(sig)
	submitted.clear()
	type_text("x")
	key(KEY_BACKSPACE)
	type_text("BOGUS")
	key(KEY_ENTER)
	check("Lag delays typing, edits and Enter", terminal.command_line.text.is_empty() and submitted.is_empty())
	await get_tree().create_timer(0.22).timeout
	check("delayed native editor preserves command order", submitted.size() == 1 and submitted[0][0] == "BOGUS" and submitted[0][1] == sig)
	check("Lag clears submitted draft", terminal.command_line.text.is_empty())
	type_text("abc")
	await get_tree().create_timer(0.18).timeout
	key(KEY_A, 0, true)
	type_text("BOGUS")
	key(KEY_ENTER)
	await get_tree().create_timer(0.18).timeout
	check("Lag retains native Ctrl+A replacement", submitted.size() == 2 and submitted[-1][0] == "BOGUS")
	# A real player can select text, pause, then type; selection must survive
	# borrowing focus between input events, not just within one replay batch.
	type_text("abc")
	await get_tree().create_timer(0.18).timeout
	key(KEY_A, 0, true)
	await get_tree().create_timer(0.18).timeout
	type_text("BOGUS")
	key(KEY_ENTER)
	await get_tree().create_timer(0.18).timeout
	check("delayed selection survives gaps between edits", submitted.size() == 3 and submitted[-1][0] == "BOGUS")
	type_text("BOGUS")
	key(KEY_ENTER)
	terminal.restore_session(terminal.root_session)
	await get_tree().create_timer(0.18).timeout
	check("background delayed Enter remains bound to host", submitted.size() == 4 and submitted[-1][1] == sig and terminal.active_signal == terminal.root_signal)
	check("background output is saved to its original history", not sig.terminal_session.history.is_empty())
	connect_host(sig)
	type_text("BOGUS")
	key(KEY_ENTER)
	close(sig)
	var count := submitted.size()
	await get_tree().create_timer(0.18).timeout
	check("disconnect cancels queued keys and commands", submitted.size() == count and not controller.sessions.has(sig.get_instance_id()))
	terminal.command_line.grab_focus()
	type_text("abc")
	check("root typing has no artificial delay", terminal.command_line.text == "abc")
	terminal.command_line.clear()

func _test_degrade_and_redact() -> void:
	var degrade := DegradeModule.new()
	degrade.ramp_sec = 0.1
	degrade.max_corruption = 1.0
	var sig := host([degrade])
	connect_host(sig)
	terminal.print_to_log("[color=orange]ORIGINAL TEXT[/color]")
	terminal.command_line.text = "HELP"
	controller.sessions[sig.get_instance_id()].age = 1.0
	controller._render_terminal()
	check("Degrade changes display while keeping source history", terminal.history.text != terminal._history_source and sig.terminal_session.history[-1] == "[color=orange]ORIGINAL TEXT[/color]")
	check("Degrade keeps formatting tags intact", "[color=orange]" in terminal.history.text and "[/color]" in terminal.history.text)
	check("Degrade input noise never changes real command", terminal.command_line.text == "HELP" and controller.input_overlay.display_text != "HELP")
	sig.disable_signal()
	check("disabling Degrade restores current terminal text and input", terminal.history.text == terminal._history_source and not controller.input_overlay.visible)
	sig.enable_signal()
	terminal._on_command_line_text_submitted(terminal.command_line.text)
	check("visually degraded HELP still submits real HELP", submitted[-1][0] == "HELP")
	close(sig)
	connect_host(sig)
	check("reconnect resets Degrade age", controller.sessions[sig.get_instance_id()].age < 0.05)
	close(sig)
	game.get_node("WindowManager").hide_help_overlay()
	var redact := RedactModule.new()
	redact.letter_fraction = 1.0
	var callback := CallbackModule.new()
	callback.apply_params({"callback_sequence": "Ab9!?"})
	sig = host([redact, callback])
	connect_host(sig)
	var source := "[color=cyan]Callback test 123: $Ab9!?[/color]"
	var display := controller.security_text(sig, source)
	check("Redact masks individual letters only", display == "[color=cyan]████████ ████ 123: $Ab9!?[/color]")
	check("Redact mask is stable", display == controller.security_text(sig, source))
	var noise := DegradeModule.new()
	noise.ramp_sec = 0.1
	noise.max_corruption = 1.0
	controller.sessions[sig.get_instance_id()].modules[&"degrade"] = noise
	controller.sessions[sig.get_instance_id()].age = 1.0
	check("Callback output stays readable with Redact plus Degrade", "$Ab9!?" in controller.terminal_text(sig, source))
	terminal.command_line.text = "HELP"
	controller._render_terminal()
	check("input display gets Degrade noise without Redact blocks", "█" not in controller.input_overlay.display_text and controller.input_overlay.display_text != "HELP")
	for layer in sig.scan_layers:
		layer.revealed = true
	sig.current_scan_index = sig.scan_layers.size()
	sig.instance_node.rebuild_tooltip()
	check("Redact covers signal tooltip without mutating scan data", "█" in sig.instance_node.tooltip_main.tt_body.text and "Callback" in sig.scan_layers[-1].description)
	terminal.print_to_log(source)
	check("Redact also covers terminal prompt but protects Callback token", "$Ab9!?" in terminal.history.text and "Callback test" not in terminal.history.text)
	terminal._refresh_signal_detail_panel()
	check("Redact covers terminal detail panel", "█" in terminal.ic_label.text)
	close(sig)
	check("disconnect restores tooltip text", "Callback" in sig.instance_node.tooltip_main.tt_body.text)

func _test_blackout_and_glitch() -> void:
	var first := host([BlackoutModule.new()])
	var second := host([BlackoutModule.new()])
	connect_host(first)
	connect_host(second)
	controller._update_signal_visuals()
	check("Blackout hides every signal and pointer target", not first.instance_node.visible and not second.instance_node.signal_icon.input_pickable)
	terminal.restore_session(terminal.root_session)
	check("Blackout survives tab switching", controller.is_blacked_out())
	close(first)
	check("closing one Blackout cannot clear another", controller.is_blacked_out() and not second.instance_node.visible)
	close(second)
	check("last Blackout restores feed", second.instance_node.visible and second.instance_node.signal_icon.input_pickable)
	var glitch := GlitchModule.new()
	glitch.position_count = 3
	glitch.jump_interval_sec = 0.5
	var sig := host([glitch])
	connect_host(sig)
	var original_position: Vector2 = sig.instance_node.position
	var collision_position: Vector2 = sig.instance_node.detection_controller.global_position
	var distance: float = manager.get_horizontal_runner_distance_cells(sig)
	controller.sessions[sig.get_instance_id()].age = 0.6
	controller._update_signal_visuals()
	check("Glitch moves visual and pointer only", sig.instance_node.shape.position != Vector2.ZERO and sig.instance_node.signal_icon.position == sig.instance_node.shape.position)
	check("Glitch leaves position, range and runner collision unchanged", sig.instance_node.position == original_position and sig.instance_node.detection_controller.global_position == collision_position and is_equal_approx(manager.get_horizontal_runner_distance_cells(sig), distance))
	var before := submitted.size()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	sig.instance_node._on_area_2d_input_event(get_viewport(), event, 0)
	var ripples := 0
	for child in manager.get_children():
		if child is GlitchRipple:
			ripples += 1
	check("fake click gives ripple without dispatching commands", ripples > 0 and submitted.size() == before)
	controller.sessions[sig.get_instance_id()].age = 1.6
	controller._update_signal_visuals()
	check("Glitch returns to real position and solid pip phase", controller.glitch_phase(sig) == 0 and sig.instance_node.shape.position == Vector2.ZERO)
	close(sig)

func _test_spammer() -> void:
	var spammer := SpammerModule.new()
	spammer.spawn_interval_sec = 0.1
	spammer.max_popups = 2
	spammer.placement = SpammerModule.Placement.TERMINAL
	var sig := host([spammer])
	connect_host(sig)
	terminal.restore_session(terminal.root_session)
	await get_tree().create_timer(0.35).timeout
	var state: Dictionary = controller.sessions[sig.get_instance_id()]
	check("Spammer continues in background and respects cap", state.popups.size() == 2)
	check("spam windows do not steal keyboard focus", terminal.command_line.has_focus())
	var region: Rect2 = terminal.get_global_rect()
	var contained := true
	for popup in state.popups:
		contained = contained and region.encloses(popup.get_global_rect())
	check("terminal-placement popups stay inside terminal", contained)
	state.popups[0].queue_free()
	await get_tree().create_timer(0.2).timeout
	check("dismissed spam respawns while connected", state.popups.size() == 2 and is_instance_valid(state.popups[-1]))
	var popups: Array = state.popups.duplicate()
	close(sig)
	await get_tree().process_frame
	check("disconnect removes every host popup", not is_instance_valid(popups[0]) and not is_instance_valid(popups[1]))

func _test_lifetime() -> void:
	var sig := host([BlackoutModule.new(), SpammerModule.new(), DegradeModule.new()])
	connect_host(sig)
	sig.disable_signal()
	check("disable cleans up all session disruptions", not controller.is_blacked_out() and not controller.sessions.has(sig.get_instance_id()))
	sig.enable_signal()
	check("re-enable restarts effects on still-open session", controller.has_effect(sig, &"blackout"))
	close(sig)

func _test_combination_and_reveal() -> void:
	var lag := LagModule.new()
	lag.delay_sec = 0.08
	var redact := RedactModule.new()
	redact.letter_fraction = 0.8
	var callback := CallbackModule.new()
	callback.apply_params({"callback_sequence": "aB1!?"})
	var spammer := SpammerModule.new()
	spammer.spawn_interval_sec = 0.1
	spammer.max_popups = 1
	var sig := host([lag, redact, callback, spammer, DegradeModule.new(), BlackoutModule.new(), GlitchModule.new()])
	terminal.restore_session(terminal.root_session)
	CommandDispatch.process_command("ACCESS " + sig.data.system_id, terminal.root_signal)
	type_text("$aB1!?")
	key(KEY_ENTER)
	type_text("OP")
	key(KEY_ENTER)
	await get_tree().create_timer(1.4).timeout
	check("combined IC preserve real Callback and queued OP during reveal", callback._resolved and not sig.data.door_locked)
	check("connection flow keeps readable Callback token in canonical history", "$aB1!?" in "\n".join(sig.terminal_session.history))
	check("combined session retains every disruption until disconnect", controller.sessions[sig.get_instance_id()].modules.size() == 6)
	close(sig)
	check("combined disconnect clears all effects and input overlay", not controller.is_blacked_out() and not controller.input_overlay.visible)
	# Also exercise the original banner buffer across a switch to root. This
	# must use its captured host rather than the tab visible at flush time.
	sig = host([])
	terminal.switch_session(sig, true)
	terminal._on_command_line_text_submitted("BOGUS")
	terminal.restore_session(terminal.root_session)
	var before := submitted.size()
	terminal._on_command_line_text_submitted("OTHER_BOGUS")
	check("background reveal does not lock root input", submitted.size() == before + 1 and submitted[-1][1] == terminal.root_signal)
	await get_tree().create_timer(0.1).timeout
	check("banner buffer stays bound to its original session", submitted[-1][0] == "BOGUS" and submitted[-1][1] == sig and terminal.active_signal == terminal.root_signal)
	close(sig)
	# Closing an in-flight reveal must not resurrect any IC on completion.
	sig = host([LagModule.new(), BlackoutModule.new()])
	terminal.switch_session(sig, true)
	close(sig)
	await get_tree().create_timer(0.1).timeout
	check("closing during reveal does not reopen disruption state", not controller.sessions.has(sig.get_instance_id()) and not controller.is_blacked_out())

func _test_lab() -> void:
	var lab = load("res://Scenes/Tests/disruptive_ic_lab.tscn").instantiate()
	add_child(lab)
	await get_tree().create_timer(1.3).timeout
	check("standalone lab initializes fresh host and two neighbors", lab.current != null and CommandDispatch.signal_manager.signal_queue.size() == 3)
	if "--capture-disruptions" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/disruptive-lab-settings.png")
	for key_name in lab.selections:
		lab.selections[key_name].button_pressed = true
	lab.include_callback = true
	lab.puzzle_type = "fuzz"
	lab.lag.delay_sec = 0.44
	lab.fresh_host()
	check("lab applies custom knobs and combined puzzle/IC", lab.current.data.ic_modules.modules.size() == 7 and lab.current.data.puzzle.puzzle_type == PuzzleComponent.Type.FUZZ and is_equal_approx(lab.current.data.ic_modules.modules[0].delay_sec, 0.44))
	check("lab has escalation disabled", not lab.game.get_node("RunManager").current_run.is_escalation_enabled())
	if "--capture-disruptions" in OS.get_cmdline_user_args():
		lab.selections.blackout.button_pressed = false
		lab.selections.lag.button_pressed = false
		lab.spammer.spawn_interval_sec = 0.3
		lab.spammer.placement = SpammerModule.Placement.TERMINAL
		lab.degrade.ramp_sec = 4.0
		lab.degrade.max_corruption = 0.25
		lab.fresh_host()
		lab.settings_panel.hide()
		CommandDispatch.process_command("ACCESS " + lab.current.data.system_id, CommandDispatch.terminal_window.root_signal)
		await get_tree().create_timer(2.0).timeout
		CommandDispatch.terminal_window.command_line.text = "RUN fuzz"
		CommandDispatch.terminal_window.disruptions._render_terminal()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/disruptive-lab-effects.png")
	lab.queue_free()
	await get_tree().process_frame
