extends Node

# Runner speed toggle (timed slow/hustle) and hidden-guard tooltips.
# Run: godot --headless --fixed-fps 60 res://Tests/speed_and_reveal_test.tscn

const PROBE_RUN := "res://Tests/Support/ResponseProbeRun.gd"

var failures := 0

func check(label: String, condition: bool) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures += 1

func _ready() -> void:
	OS.set_environment("NULL_RESPONSE_PROBE", "far_guard")
	var run_main: Node = load("res://Scenes/run_main.tscn").instantiate()
	run_main.get_node("RunManager").level_script_path = PROBE_RUN
	run_main.get_node("TutorialManager").set_script(null)
	add_child(run_main)
	await _frames(10)
	var timeline = run_main.get_node("SignalTimeline/TimelineManager")
	var sm = run_main.get_node("SignalTimeline/SignalManager")

	# --- hidden guard: the disruption visuals update runs every frame ---
	var guard: ActiveSignal = null
	for sig in sm.signal_queue:
		if sig.data.system_id == "probe":
			guard = sig
	check("guard is on screen", guard != null and guard.instance_node != null)
	if guard != null and guard.instance_node != null:
		var node = guard.instance_node
		check("unrevealed guard keeps its tooltip hidden", not node._guard_revealed and not node.tooltip_main.visible)
		check("unrevealed guard can't be clicked", not node.signal_icon.input_pickable)
		node.show_hover_tooltip()
		check("hovering a hidden guard shows nothing", not node.tooltip_main.visible)
		# Blocks from different systems combine; clearing one keeps the other.
		node.apply_disruption_visuals(Vector2.ZERO, false, false, true)
		check("blackout hides the whole guard", not node.visible)
		node.apply_disruption_visuals(Vector2.ZERO, false, false, false)
		check("ending blackout restores the entity but keeps the guard hidden", node.visible and not node.tooltip_main.visible and not node.signal_icon.input_pickable)
		node.set_guard_revealed(true)
		check("revealed guard shows its tooltip", node.tooltip_main.visible and node.signal_icon.input_pickable)
		# Any other system's block survives the per-frame updates.
		node.set_display_block(&"test_block", node.BLOCK_TOOLTIP | node.BLOCK_PICK)
		await _frames(30)
		check("a block survives frames of reveal/disruption updates", not node.tooltip_main.visible and not node.signal_icon.input_pickable)
		node.set_display_block(&"test_block", 0)
		# In play the guard re-hid itself meanwhile (runner far, no camera), so
		# the only block left is that one, and it resolves to what it says.
		check("clearing a block leaves only the others", node._display_blocks.keys() == [&"hidden_guard"] and not node.tooltip_main.visible)
		node.set_guard_revealed(true)
		check("with no blocks left the tooltip and icon are back", node._display_blocks.is_empty() and node.tooltip_main.visible and node.signal_icon.input_pickable)
		var disruptions = CommandDispatch.terminal_window.disruptions
		check("idle disruption controller tracks nothing", disruptions.sessions.is_empty() and disruptions._applied_visuals.is_empty())
		node.set_guard_revealed(false)

	# --- speed toggle ---
	var bar: RunnerSpeedBar = run_main.get_node_or_null("SignalTimeline/GridLayer/RunnerTeam/SpeedBar")
	check("runner has a speed countdown bar", bar != null and bar.timeline_manager == timeline)
	# Real key events through the viewport, with the command line focused as
	# in play, so the terminal bypass is exercised too.
	var line: LineEdit = CommandDispatch.terminal_window.command_line
	line.grab_focus()
	line.text = "ACCESS cam_01"
	line.caret_column = 6
	await _key(KEY_UP)
	check("UP starts hustle", timeline.speed_mode == &"hustle" and is_equal_approx(timeline.current_speed_mult, timeline.fast_speed_modifier))
	check("UP doesn't touch the command line caret", line.caret_column == 6 and line.text == "ACCESS cam_01")
	await _frames(int(10.0 * 60))
	check("hustle still on after 10s without holding", timeline.speed_mode == &"hustle")
	await _key(KEY_UP)
	check("pressing again refreshes to the full duration", timeline.speed_time_left > timeline.speed_toggle_sec - 0.5)
	await _frames(int(14.0 * 60))
	check("refreshed hustle outlasts the original 15s", timeline.speed_mode == &"hustle")
	await _frames(int(2.0 * 60))
	check("hustle expires back to walking", timeline.speed_mode == &"walk" and is_equal_approx(timeline.current_speed_mult, 1.0))
	await _key(KEY_DOWN)
	check("DOWN starts a timed slow", timeline.speed_mode == &"slow" and is_equal_approx(timeline.current_speed_mult, timeline.slow_speed_modifier))
	check("DOWN doesn't touch the command line caret", line.caret_column == 6)
	await _key(KEY_UP)
	check("UP from a slowdown returns to walking", timeline.speed_mode == &"walk")
	await _key(KEY_UP)
	await _key(KEY_DOWN)
	check("DOWN from a hustle returns to walking", timeline.speed_mode == &"walk")
	await _key(KEY_LEFT)
	await _key(KEY_RIGHT)
	check("left/right no longer change speed", timeline.speed_mode == &"walk")
	timeline.clear_speed_mode()
	line.text = ""

	# --- Null Spike: tap Ctrl ---
	check("null spike starts off", not timeline.null_spike_active)
	await _key(KEY_CTRL)
	check("tapping Ctrl activates the Null Spike", timeline.null_spike_active)
	await _key(KEY_CTRL)
	check("tapping Ctrl again deactivates it", not timeline.null_spike_active)
	# Ctrl as a modifier (paste) is not a tap.
	_send(KEY_CTRL, true)
	await get_tree().process_frame
	_send(KEY_V, true, true)
	_send(KEY_V, false, true)
	_send(KEY_CTRL, false)
	await _frames(3)
	check("Ctrl+V doesn't toggle the Null Spike", not timeline.null_spike_active)
	await _key(KEY_SHIFT)
	check("Shift no longer toggles the Null Spike", not timeline.null_spike_active)
	Engine.time_scale = 1.0

	print("SPEED/REVEAL TEST: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _send(code: Key, pressed: bool, ctrl := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.ctrl_pressed = ctrl
	Input.parse_input_event(event)

func _key(code: Key) -> void:
	_send(code, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_send(code, false)
	await get_tree().process_frame

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
