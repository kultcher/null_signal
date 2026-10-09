extends Node
# Regression checks for existing IC + command dispatch after the resolver changes.

var run_main: Node
var timeline
var sm
var term
var heat_mgr
var results: Array[String] = []
var errors: Array = []
var completes: Array = []
var fails := 0

func _ready() -> void:
	run_main = load("res://Scenes/run_main.tscn").instantiate()
	run_main.get_node("RunManager").level_script_path = "res://Resources/RunData/AuthoredRuns/TestRun.gd"
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
	for id in [&"codex_faraday", &"codex_trace", &"codex_bouncer", &"codex_callback", &"codex_haze", &"codex_reboot"]:
		PlayerData.codex_popup_seen[id] = true
	CommandDispatch.command_error.connect(func(msg, ctx): errors.append([msg, ctx]))
	CommandDispatch.command_complete.connect(func(c): completes.append(c))
	timeline.set_runner_cell(0.0)
	await _wait(0.3)

	var cam05 := _sig("cam_05")
	var cam03 := _sig("cam_03")
	var cam04 := _sig("cam_04")

	# 1. explicit-target KILL from root
	var h0 := _heat()
	completes.clear()
	await _cmd("KILL cam_05")
	_check("KILL explicit: disables", cam05.is_disabled)
	_check("KILL explicit: terminal switched to target", term.active_signal == cam05)
	var log_lines := []
	for c in completes:
		log_lines.append_array(c.log_text)
	_check("KILL explicit: 'Shutting down' reported", " ".join(log_lines).contains("Shutting down cam_05"), str(log_lines))
	_check("KILL explicit: heat 500", absf(_heat() - h0 - 500.0) < 5.0, "dh=%.0f" % (_heat() - h0))

	# 2. Faraday blocks a far command; error goes to the session typed in
	errors.clear()
	await _cmd("KILL cam_03")
	_check("faraday: far KILL blocked", not cam03.is_disabled)
	_check("faraday: no session switch on failure", term.active_signal == cam05)
	_check("faraday: error reported in origin session", errors.size() > 0 and errors[-1][1] == cam05 and str(errors[-1][0]).contains("FARADAY"), str(errors))

	# 3. Door KILL failure stays put
	# (TestRun has no door; skip)

	# 4. Bouncer disconnects
	await _cmd("ACC cam_04")
	await _wait(1.0)
	_check("bouncer: connected", term.active_signal == cam04)
	await _wait(6.0)
	_check("bouncer: forced disconnect", cam04.terminal_session == null or not cam04.terminal_session.has_tab)

	# 5. Callback gate then KILL
	await _cmd("ACC cam_04")
	await _wait(2.5)
	errors.clear()
	await _cmd("KILL")
	_check("callback: KILL blocked until callback", not cam04.is_disabled and errors.size() > 0 and str(errors[-1][0]).contains("CALLBACK"), str(errors))
	var cb: CallbackModule = cam04.data.ic_modules.modules[1]
	await _cmd("$" + cb.callback_sequence)
	await _cmd("KILL")
	_check("callback: KILL works after callback", cam04.is_disabled)

	# 6. Reboot
	await _wait(10.5 - 9.5)
	var waited := 0.0
	while cam05.is_disabled and waited < 12.0:
		await _wait(0.5)
		waited += 0.5
	_check("reboot: cam_05 restored", not cam05.is_disabled, "waited %.1fs more" % waited)

	print("REGTEST ================")
	for r in results:
		print("REGTEST ", r)
	print("REGTEST fails=", fails)
	get_tree().quit()

func _check(name: String, ok: bool, detail: String = "") -> void:
	results.append(("PASS " if ok else "FAIL ") + name + ("" if detail.is_empty() else "  (" + detail + ")"))
	if not ok:
		fails += 1

func _sig(id: String) -> ActiveSignal:
	return sm.get_signal_by_system_id(id)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _cmd(text: String) -> void:
	CommandDispatch.process_command(text, term.active_signal)
	await get_tree().process_frame

func _heat() -> float:
	return heat_mgr.get_heat()
