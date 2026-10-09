extends Node
# Functional test for the IC expansion: drives the IC test run through real
# terminal commands / scans / timers and checks outcomes.

var run_main: Node
var timeline
var sm
var term
var heat_mgr
var results: Array[String] = []
var errors: Array = []
var fails := 0

func _ready() -> void:
	var packed: PackedScene = load("res://Scenes/run_main.tscn")
	run_main = packed.instantiate()
	run_main.get_node("RunManager").level_script_path = "res://Resources/RunData/AuthoredRuns/ICTestRun.gd"
	add_child(run_main)
	await get_tree().process_frame
	await get_tree().process_frame
	timeline = run_main.get_node("SignalTimeline/TimelineManager")
	sm = run_main.get_node("SignalTimeline/SignalManager")
	term = CommandDispatch.terminal_window
	heat_mgr = run_main.get_node("HeatManager")
	timeline.BASE_CELLS_PER_SECOND = 0.0
	timeline.cells_per_second = 0.0
	ActionResolver.debug_logging = false
	for id in [&"codex_tripwire", &"codex_siphon", &"codex_heartbeat", &"codex_tether", &"codex_shy", &"codex_reboot"]:
		PlayerData.codex_popup_seen[id] = true
	CommandDispatch.command_error.connect(func(msg, ctx): errors.append([msg, ctx]))

	await _test_tripwire()
	await _test_siphon()
	await _test_heartbeat()
	await _test_tether()
	await _test_shy()

	print("ICTEST ================")
	for r in results:
		print("ICTEST ", r)
	print("ICTEST fails=", fails)
	get_tree().quit()

func _check(name: String, ok: bool, detail: String = "") -> void:
	results.append(("PASS " if ok else "FAIL ") + name + ("" if detail.is_empty() else "  (" + detail + ")"))
	if not ok:
		fails += 1

func _sig(id: String) -> ActiveSignal:
	return sm.get_signal_by_system_id(id)

func _goto(cell: float) -> void:
	timeline.set_runner_cell(cell)
	await _wait(0.3)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _cmd(text: String) -> void:
	CommandDispatch.process_command(text, term.active_signal)
	await get_tree().process_frame

func _connect(id: String) -> void:
	await _cmd("ACC " + id)
	await _wait(2.5)  # connection flow, then IC on_connect

func _heat() -> float:
	return heat_mgr.get_heat()

func _test_tripwire() -> void:
	await _goto(2.0)
	var h0 := _heat()
	await _cmd("KILL cam_trip")
	await _wait(0.2)
	var dh := _heat() - h0
	_check("tripwire: KILL disables", _sig("cam_trip").is_disabled)
	_check("tripwire: KILL heat (500) + tripwire spike (900)", dh >= 1390.0 and dh < 1450.0, "dh=%.0f" % dh)

func _test_siphon() -> void:
	await _goto(8.0)
	await _connect("door_siphon")
	var h0 := _heat()
	await _wait(3.0)
	var dh := _heat() - h0
	_check("siphon: bleeds ~60/s while connected", dh >= 150.0 and dh <= 260.0, "dh=%.0f over 3s" % dh)
	var no_lines: Array[String] = []
	term.force_disconnect_signal(_sig("door_siphon"), no_lines)
	await _wait(1.5)
	var h1 := _heat()
	await _wait(2.0)
	var dh2 := _heat() - h1
	_check("siphon: stops after disconnect", dh2 < 40.0, "dh=%.0f over 2s" % dh2)

func _test_heartbeat() -> void:
	await _goto(14.0)
	var cam := _sig("cam_heart")
	var mod: HeartbeatModule = cam.data.ic_modules.modules[0]
	# Wait for a beat, then kill right after it.
	var waited := 0.0
	while mod.timer == null or mod.timer.time_left > mod.beat_interval_sec - 0.3:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited > 15.0:
			break
	await _cmd("KILL cam_heart")
	_check("heartbeat: KILL disables", cam.is_disabled)
	await _wait(mod.beat_interval_sec - 1.5)
	_check("heartbeat: stays down until the next pulse", cam.is_disabled)
	var h0 := _heat()
	await _wait(2.0)
	_check("heartbeat: pulse restores node", not cam.is_disabled)
	var dh := _heat() - h0
	_check("heartbeat: tamper heat on pulse", dh >= 190.0 and dh < 260.0, "dh=%.0f" % dh)

func _test_tether() -> void:
	await _goto(20.0)
	await _connect("door_tether")
	var door := _sig("door_tether")
	var cam := _sig("cam_tether_watch")
	_check("tether: connected to door", term.active_signal == door)
	errors.clear()
	await _cmd("KILL cam_tether_watch")
	_check("tether: KILL on other signal blocked", not cam.is_disabled)
	_check("tether: terminal stays on tethered door", term.active_signal == door)
	_check("tether: block message shown in door session", errors.size() > 0 and str(errors[-1][0]).contains("TETHER") and errors[-1][1] == door, str(errors))
	errors.clear()
	await _cmd("ACC cam_tether_watch")
	_check("tether: ACCESS to other signal blocked", term.active_signal == door, str(errors))
	var h0 := _heat()
	var no_lines: Array[String] = []
	term.force_disconnect_signal(door, no_lines)
	await _wait(1.5)
	var dh := _heat() - h0
	_check("tether: early disconnect penalty (300)", dh >= 290.0 and dh < 340.0, "dh=%.0f" % dh)
	await _cmd("KILL cam_tether_watch")
	await _wait(0.2)
	_check("tether: released after disconnect", cam.is_disabled)

func _test_shy() -> void:
	await _goto(28.0)
	var cam := _sig("cam_shy")
	var scan = run_main.get_node("SignalTimeline/ScanController")
	scan.toggle_scan(cam)
	var waited := 0.0
	while cam.current_scan_index < cam.scan_layers.size() and waited < 10.0:
		await _wait(0.1)
		waited += 0.1
	_check("shy: full scan completes", cam.current_scan_index >= cam.scan_layers.size(), "%d/%d" % [cam.current_scan_index, cam.scan_layers.size()])
	_check("shy: IC readable right after scan", cam.is_scan_layer_revealed("IC"))
	var mod: ShyModule = cam.data.ic_modules.modules[1]
	await _wait(mod.hide_delay_sec + 0.5)
	_check("shy: scan data scrubbed after delay", cam.current_scan_index == 0 and not cam.is_scan_layer_revealed("IC"))
	_check("shy: tooltip body cleared", cam.instance_node != null and cam.instance_node.tooltip_main.tt_body.text.strip_edges() == "", "body='%s'" % cam.instance_node.tooltip_main.tt_body.text.strip_edges())
