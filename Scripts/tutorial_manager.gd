# tutorial_manager.gd

extends Node

const NULL_SPIKE_DUMP_PATH := "res://Resources/RunData/AuthoredRuns/null_spike_dump.md"
const NULL_SPIKE_SYNC_PATH := "res://Resources/RunData/AuthoredRuns/null_spike_sync.md"

@export_enum("full", "door_01", "cam_02", "drone_01", "null_door", "lab_reveal", "terminal_dump", "alarm", "pre_gauntlet", "gauntlet") var debug_skip_to_stage := "full"

@onready var timeline_manager = $"../SignalTimeline/TimelineManager"
@onready var signal_manager = $"../SignalTimeline/SignalManager"
@onready var terminal_window = $"../WorkspaceAnchor/TerminalWindow"
@onready var run_manager = $"../RunManager"
@onready var window_manager = $"../WindowManager"

@onready var cutscene_controller = $"../CutsceneController"

@onready var runner_focus_panel = $"../SignalTimeline/GridLayer/RunnerTeam/PanelContainer"
@onready var heat_tracker = $"../HeatTracker"

var _active_runner_hold_tokens: Dictionary = {}

signal wait_completed(result: String)

func _ready():
	GlobalEvents.reset_tutorial_features()
	window_manager.clear_tutorial_objective()
	if run_manager.get_run_id() == "tutorial":
		GlobalEvents.first_null_spike = true
		_set_cutscene_black_screen(true)
		call_deferred("_run_tutorial_sequence")
	else:
		_set_cutscene_black_screen(false)

func _run_tutorial_sequence() -> void:
	_disable_tutorial_features()
	match debug_skip_to_stage:
		"door_01":
			_prepare_debug_stage_door_01()
			await _run_door_01_sequence()
			await _run_cam_02_intro_sequence()
		"cam_02":
			_prepare_debug_stage_cam_02()
			await _run_cam_02_intro_sequence()
		"drone_01":
			_prepare_debug_stage_drone_01()
			await _run_drone_01_intro_sequence()
		"null_door":
			_prepare_debug_stage_null_door()
			await _run_null_door_intro_sequence()			
		"lab_reveal":
			_prepare_debug_stage_lab_reveal()
			await _run_lab_reveal_sequence()
		"terminal_dump":
			_prepare_debug_stage_terminal_dump()
			await _run_terminal_dump_sequence()
		"alarm":
			_prepare_debug_stage_alarm()
			await _run_alarm_sequence()
		"pre_gauntlet":
			_prepare_debug_pre_gauntlet()
			await _run_pre_gauntlet_sequence()
		"gauntlet":
			_prepare_debug_gauntlet()
			await _run_gauntlet_sequence()
		_:
			await _run_intro_sequence()
			await _run_cam_01_sequence()
			await _run_door_01_sequence()
			await _run_cam_02_intro_sequence()
			await _run_drone_01_intro_sequence()
			await _run_null_door_intro_sequence()
			await _run_lab_reveal_sequence()
			#await _run_terminal_dump_sequence()
			await _run_alarm_sequence()
			await _run_pre_gauntlet_sequence()
			await _run_gauntlet_sequence()

func _run_intro_sequence() -> void:
	_set_runner_cell(-1)
	_acquire_runner_hold("intro")
	signal_manager.hide_signals()
	_set_cutscene_black_screen(true)
	await _show_dialogue([
		"All right kid, you ready for the real deal?"
	], "", Rect2(), _center_dialogue_pos(), true)

	await cutscene_controller.play_intro_glitch_transition(3)
	signal_manager.show_signals()

	await _show_dialogue([
		"Just like the sims, right? Only if you fuck it up, it might actually get me killed. No pressure.",
		"Don't sweat it, should be a milk run. We'll take it nice and slow, and not just because I'm getting old."
	], "", Rect2(), _center_dialogue_pos(), true)

	_release_runner_hold("intro")
	await get_tree().create_timer(1.0).timeout
	_focus_runner()
	var intro_lines: Array[String] = [
		"All right, I'm on the move. You should already be seeing some network SIGNALs registering on the timeline.",
		"It'll look they're moving toward me, but it's all relative\u2014I'm moving toward them. The stationary ones, anyway."
	]
	if timeline_manager.map_mode:
		intro_lines = [
			"All right, I'm on the move. You should already be seeing the floorplan, and some network SIGNALs registering on it.",
			"Your feed's locked on me, so the map moves as I do. Whatever's to my right, I'm walking into."
		]
	await _show_dialogue(intro_lines, "", window_manager.get_control_focus_rect(runner_focus_panel), Vector2(), false, 2, "intro_walk_and_talk")
	_set_objective("- Wait for Blackjack to get into position\n- Hold the [color=cyan]-> arrow key[/color] to tell him to hustle.")

func _run_cam_01_sequence() -> void:
	await _wait_for_cell(1)
	_acquire_runner_hold("cam_01_gate")
	await _show_dialogue([
		"Eyes on two cameras. One is off the main route, so it shouldn't be an issue, but the other is right above the facility door.",
		"We'll need to take it out, but give it a scan first. Always check for access blocks. Or worse, ICE.\n\n[color=cyan]<Right Click>[/color] to scan."
	], "cam_01")
	_set_objective("- [color=cyan]Right click[/color] the cam_01 signal to scan it.")
	_enable_feature("scan")

	await _wait_for_scan_complete("cam_01")
	await _show_dialogue([
		"Good. Unlocked, no ICE. Probably no one watching, either, but who knows with these old AI husks.",
		"Some of them are still crawling with drones and turrets. Well, 'spose turrets don't crawl. That I've seen.",
		"You know the drill. Connect to that camera and [color=orange]KILL[/color] it.\n\n[color=cyan]<Left Click>[/color] to connect, then type [color=orange]KILL[/color] in the terminal and press enter.\n"
	], "cam_01")
	_set_objective("- [color=cyan]Left click[/color] the cam_01 signal to connect, then type [color=orange]KILL[/color] in the terminal.")
	_enable_feature("connect")
	_enable_feature("terminal_commands")

	await _wait_for_signal_killed("cam_01")
	_release_runner_hold("cam_01_gate")
	await get_tree().create_timer(1.0).timeout

	await _show_dialogue([
		"Simple as. Just watch your heat. KILL is noisy, and more network noise means more attention from the system.",
		"Runners don't like attention. For you, it might just mean more ICE. For us, it tends to come with bullet holes."
	], "", Rect2(Vector2(0,1030), Vector2(100,5)), Vector2(50, 700), true, 5, "door_walk_and_talk")
	_set_objective("- Wait for Blackjack to move ahead\n- Hold the [color=cyan]-> arrow key[/color] to tell him to hustle.")


func _run_door_01_sequence() -> void:
	await _wait_for_cell(6)
	_acquire_runner_hold("door_01_gate")

	window_manager.auto_focus_puzzles = true


	await _show_dialogue([
		"All right, facility door in sight. Give it a scan, if you haven't already."
	], "door_01")
	_set_objective("- [color=cyan]Right click[/color] door_01 signal to scan it")

	await _wait_for_scan_complete("door_01")
	_focus_door_lock_state("door_01")
	
	await _show_dialogue([
		"Locked, obviously. Different locks require different keys.",
		"This one auth-locked. Means the credentials are floating around the network, we just need to sniff out the right data. [color=orange]RUN sniff[/color] in your terminal to find it."
	], "door_01")
	_set_objective("- Left click the door_01 signal to connect, then type [color=orange]RUN sniff[/color] in the terminal to run the Sniff program.\nWhen connected to a locked signal, you can also click on the Lock status panel below the terminal to pull up a clickable list of unlocking programs.")

	await _wait_for_puzzle_started(PuzzleComponent.Type.SNIFF)

	await _show_dialogue([
		"Sniff's simple. The program will tell you the target data, you just need to track it in the datastreams. Simple as."
	], "door_01")
	_set_objective("- Find and click the targeted hex code.")

	await _wait_for_puzzle_solved("door_01")
	window_manager.clear_focus_overlay()
	window_manager.auto_focus_puzzles = false

	await _show_dialogue([
		"Now you've got access, but you still need to unlock the door in realspace.",
		"A lot of signals have a basic functionality that you can access with the [color=orange]OPERATE[/color] command, or [color=orange]OP[/color] for short."
	], "door_01")
	_set_objective("- Make sure you're connected to the door_01 signal and type [color=orange]OP[/color] to unlock the door")

	await _wait_for_door_unlocked("door_01")
	_release_runner_hold("door_01_gate")
	_focus_runner()
	await _show_dialogue([
		"See? Milk run, like I said.",
		"By the way, while you'll be doing a lot of unlocking, OP can also lock doors. You'd be surprised how often that comes in handy.",
		"Heading inside. Tracking another camera. You know the drill. Scan away."
	], "", window_manager.get_control_focus_rect(runner_focus_panel), Vector2(), false, 9, "cam_02_walk_and_talk")
	_set_objective("")

func _run_cam_02_intro_sequence() -> void:
	await _wait_for_cell(10)
	_acquire_runner_hold("cam_02_gate")
	await _show_dialogue([
		"Camera ahead, covering the hall. Give it a scan." if timeline_manager.map_mode else "Camera ahead, center lane. Give it a scan."
	], "cam_02")
	_set_objective("- Right click the cam_02 signal to scan it")
	await _wait_for_scan_complete("cam_02")

	await _show_dialogue([
			"This one's got ICE. Not too dangerous. Reboot: does just what it says. If the Signal goes down, it automatically gets rebooted after a short window.",
			"This camera is panning, too. Your call how to handle it.",
			"You can KILL it and take the heat and I'll move past while it reboots, or you can let me know when it's safe to slip by while the camera pans away."
		], "cam_02")
	_set_objective("- Connect to cam_02 and KILL it OR\n- Hold -> to have Blackjack hustle past while the camera is panned away")

	_enable_feature("terminal_commands", true)
	
	GlobalEvents.runner_detected.connect(_runner_detected_dialogue, CONNECT_ONE_SHOT)

	await _cam_02_kill_or_hustle(_get_active_signal("cam_02"))
	_release_runner_hold("cam_02_gate")

func _run_drone_01_intro_sequence():
	# TODO: Build into tutorial run def at some point
	var vent = _get_active_signal("coolant_vent_01")
	vent.data.disruptor.set_uses(5)
	await _wait_for_cell(13)
	# NOTE: Something preventing this hold?
	_acquire_runner_hold("drone_01_gate")
	await _show_dialogue([
		"Shit, picking up a drone. Could be armed. They're mobile and not as predictable as cameras. Give it a scan."
	], "drone_01")
	_set_objective("Right click to scan the drone_01 signal")

	await _wait_for_scan_complete("drone_01")

	await _show_dialogue([
		"Reboot IC on a 3-second timer. KILL wouldn't buy us much time here. Fortunately, drones do respond to unexpected stimuli. We can use that."
	], "drone_01")
	
	await _show_dialogue([
		"Connect to that coolant vent and flush it with the OP command. It should be noisy enough to draw the drone away for more than 3 seconds and let me slip past."
	], "coolant_vent_01")
	_set_objective("Connect to the coolant_vent_01 signal and type OP to create a distraction")

	await GlobalEvents.mobile_investigating
	_release_runner_hold("drone_01_gate")

	await _wait_for_cell(16.5)
	await _set_objective("- Help Blackjack through the gauntlet
- Use the <- and -> arrow keys to have Blackjack slow down or speed up
- Press F1 if you need a refresher on terminal commands")
	await _show_dialogue([
		"Long corridor coming up, lots of cameras and a few drones. No more hand-holding, kid. Let's see what you've got.",
	], "", Rect2(), Vector2(), false, 17.5)

	# pre-lab gauntlet (38.5 - 59.5)




func _run_null_door_intro_sequence():

	await _wait_for_cell(38)
	_enable_feature("terminal_commands", false)
	await _show_dialogue([
		"Phew. All right. I think we're past the hard part. Coming up on... some kind of clean lab? Let's have a look.",
		"Sniff out that door's key, like last time."
	], "lab_door", Rect2(), Vector2(), false, 40, "null_lab_leadup")
	_set_objective("- Connect to the lab_door signal and RUN sniff to unlock it\n- Once unlocked, use OP to open the door")

	window_manager.auto_focus_puzzles = false

	await _wait_for_cell(40)
	_acquire_runner_hold("lab_door_gate_01")

	_enable_feature("terminal_commands", true)

	await _wait_for_puzzle_started(PuzzleComponent.Type.SNIFF)

	await _show_dialogue([
		"Whoa. This one is locked down much tighter.",
		"... Huh. What were the ghosts hiding down here?"
	], "", Rect2(), Vector2(350, 400), true)
	
	await _wait_for_door_unlocked("lab_door")
	_release_runner_hold("lab_door_gate_01")
	
	# preventing sequence break by decrypting terminal early
	_enable_feature("terminal_commands", false)

	await _wait_for_cell(42.5)

	_acquire_runner_hold("null_terminal_gate_01")

	await _show_dialogue([
		"...",
		"What the fuck...?",
	], "", Rect2(), _center_dialogue_pos(), true, 43.5, "null_lab_leadup")
	_release_runner_hold("null_terminal_gate_01")


func _run_lab_reveal_sequence() -> void:
	# make sure null terminal is fully scanned (mostly for using lock toolbox)
	var null_term = _get_active_signal("null_terminal")
	for l in null_term.scan_layers:
		l.revealed = true

	# prevent player from closing null term tab or switching tabs
	terminal_window.session_tabs.set_mouse_filter(Control.MOUSE_FILTER_IGNORE)
	terminal_window.root_tab.set_mouse_filter(Control.MOUSE_FILTER_IGNORE)

	await _wait_for_cell(46)
	_acquire_runner_hold("null_terminal_gate_02")
	await _show_dialogue([
		"Some kind of cyberware... like a datajack interface? An... adapter?",
		"...",
		"I found a terminal here to kill the local security. The cameras and drones should be out.",
		"You need to come inside and see this."
	], "", Rect2(), _center_dialogue_pos(), true)

	GlobalEvents.heat_set_requested.emit(0)
	window_manager.objective_tracker.hide()

	await get_tree().create_timer(1).timeout

	signal_manager.hide_signals()
	await cutscene_controller.play_reverse_glitch_transition(2.0)

	await _show_dialogue([
		"Been going through the specs on this thing. They called it a... [i][b]the[/b][/i] \"Null Spike.\"",
		"It's... I'm reading this in English, kid. They wrote specs in English and never shared this with us.",
		"...",
		"You're too young to remember, but the AIs starting to speak their own language before they left. One we didn't... maybe couldn't understand.",
		"If I'm reading this right... this thing was meant meant to translate. To interface.",
		"Some of the files are encrypted. Need your deck if we're going to crack them."
	], "", Rect2(), _center_dialogue_pos(), true)

	await get_tree().create_timer(1).timeout
	await cutscene_controller.play_still_reveal(2.2)

	await _show_dialogue([
		"Take a look at this place, huh? Drones in here living better than most upstackers.",
		"... Anyway.",
		"This works out, actually — you can try the DECRYPT program without someone's life on the line. Plug in directly, I'll walk you through it.",
		"It's just like the Sniff program from earlier, just RUN decrypt in the terminal."
	], "", Rect2(), _center_dialogue_pos(), true)
	window_manager.objective_tracker.show()
	_set_objective("RUN decrypt on the null_terminal")

	_enable_feature("terminal_commands", true)
	terminal_window.z_index = 100
	terminal_window.switch_session(_get_active_signal("null_terminal"))

	await _wait_for_puzzle_started(PuzzleComponent.Type.DECRYPT)

	await _show_dialogue([
		"See that grid? Program's already working on cracking it. It predicts all the possible characters that could fit the cipher down near the bottom. It'll chip away on its own, but slowly.",
		"You want to speed it up, you can input values manually. Look for the pattern. If you figure out what one letter maps to, plug it in and the whole thing accelerates.",
		"On a real run, you wanna start decrypt early so the program does most of the work for you. But I promise there'll be times when quickly cracking a cipher will save their asses."
		], "", Rect2(), Vector2(350,400), true)
	_set_objective("Solve the encrypted cipher")

	await _wait_for_puzzle_solved("null_terminal")
	window_manager.objective_tracker.hide()

	# reenable tabs
	terminal_window.session_tabs.set_mouse_filter(Control.MOUSE_FILTER_STOP)
	terminal_window.root_tab.set_mouse_filter(Control.MOUSE_FILTER_STOP)


	await _run_terminal_dump_sequence()
	await get_tree().create_timer(2).timeout
	terminal_window.z_index = 0

	await _show_dialogue([
		"...",
		"Kid. If this does what I think it does... this is the most important piece of tech anyone's found since the AIs clipped off and left us to drift.",
		"This could change everything...",
		"...Or at least be worth more than either of us will see in a lifetime.",
		"We'll figure out what to do with it when we're home. For now, let's grab it and go. I'm disengaging the lock."
		], "", Rect2(), _center_dialogue_pos(), true)

	await get_tree().create_timer(2).timeout
	print("timer")
	

func _run_alarm_sequence():
	print("cutscene start")

	_start_cutscene_alarm()
	print("cutscene end")

	await _show_dialogue([
		"Shit. See, this is why we always scan before we mess with things. Now we caught the light.",
		"Facility's locking down and... That's a lot of drones.",
		"...",
		"Seeing a manual shutdown on this terminal. Air-gapped, so no remote access — I'll have to get to it on foot. Jack in, kid. Gonna need your eyes."
	], "", Rect2(), _center_dialogue_pos(), true)

	await get_tree().create_timer(2).timeout
	
	_set_runner_cell(47.5)
	_get_active_signal("lab_exit").set_door_locked(false)
	_get_active_signal("lab_exit").disable_signal()

	_release_runner_hold("null_terminal_gate_02")

	await cutscene_controller.play_cutscene_return_transition(2.5, 1)
	signal_manager.show_signals()

	# killer drone setup
	var c_drone = _get_active_signal("c_drone_01").data
	c_drone.detection.turn_speed_deg_per_sec = 270.0
	c_drone.mobility.move_speed_cells_per_sec = 0
	
	_get_active_signal("coolant_vent_07").disable_signal()
		
	await _wait_for_cell(49.5)
	_enable_feature("terminal_commands", true)

	await _show_dialogue([
		"Clip, they woke up angry. Can hear 'em clanking.",
		"Incoming. See what you can do, kid."
	], "", Rect2(), _center_dialogue_pos(), true, 50.5)
	window_manager.objective_tracker.show()

	_set_objective("Try to stop the combat drone")

	await _wait_for_cell(50.5)
	c_drone.mobility.move_speed_cells_per_sec = .25
	await _wait_for_cell(51.5)

	var temp_dialogue = await _show_dialogue([
		"Clip me. It's fast. And armed. And probably ICEd."
	], "c_drone_01", Rect2(), Vector2(), false, -1, "", 3)
	
	temp_dialogue = await _show_dialogue([
		"It's almost on me. Kid!?"
	], "", Rect2(), _center_dialogue_pos(), true, -1, "", 3)

	# NOTE: Make sure this can't get set by anything other than the drone combat
	await GlobalEvents.runners_stopped
	_acquire_runner_hold("post_combat")

	temp_dialogue = await _show_dialogue([
			"Manual override it is!"
		], "", Rect2(), _center_dialogue_pos(), true, -1, "", 3)

	await get_tree().create_timer(4)

	await _show_dialogue([
		"Ngh...",
		"... I'm all right. Still moving. And kid...",
		"Nothing you could've done. What you can't solve gets solved on the ground. That's my half of the job."
		], "", window_manager.get_control_focus_rect(runner_focus_panel))

	await get_tree().create_timer(1.5)
	_release_runner_hold("post_combat")

func _run_pre_gauntlet_sequence():
	await _wait_for_cell(56.5)
	_acquire_runner_hold("pre_gauntlet_01")

	await _show_dialogue([
		"You've gotta be kidding me."
	], "", Rect2(), _center_dialogue_pos(), true)

	await get_tree().create_timer(.5).timeout

	await timeline_manager.set_view_offset_cells(10, 2.0)

	# speed up gauntlet drones
	for sig in signal_manager.signal_queue:
		if sig.data.display_name.contains("c_drone"):
			sig.data.detection.turn_speed_deg_per_sec = 270.0

	await _show_dialogue([
		"...",
		"Okay. Okay, listen.\n\nI only see one way we get out of this.",
		"You use the Null Spike.",
		"Not gonna lie, it's risky. [b]If[/b] I understood it right and [b]if[/b] it actually works...",
		"You might be able to see the network the way the ghosters did when they built it. Or as close to that as a human is capable."
	], "", Rect2(), _center_dialogue_pos(), true)

	await get_tree().create_timer(2)
	timeline_manager.clear_view_offset(1.0)

	_release_runner_hold("pre_gauntlet_01")
	await _wait_for_cell(57)
	_acquire_runner_hold("pre_gauntlet_02")

	_enable_feature("terminal_commands", false)

	_set_objective("- Type INTERFACE NS_01a.sys -u -c into the terminal to install the Null Spike")
	await _show_dialogue([
		"...I swear I'd do it myself if I could.",
		"Never told you how my 'jack got fried, did I? Used to work on stuff like this. Interfacing with them. We never solved it... Guess maybe they did.",
		"Burnt me out. That's why you're in the chair and I'm bleeding here.",
		"And I'm asking you to do the same thing. With tech we found minutes ago in a place the AIs never meant for us to find.",
		"...I'm sorry kid. Wouldn't ask if I saw another way.",
		"If you want to do this, you'll need to prep your deck. [b][color=cyan]INTERFACE NS_01a.sys -u -c[/color][/b]\nThen plug back in."
	], "",  window_manager.get_control_focus_rect(runner_focus_panel), _center_dialogue_pos(), true)

	_enable_feature("terminal_commands", true)
	
	await GlobalEvents.null_spike_init
	await get_tree().create_timer(2)
	await cutscene_controller.play_null_spike_init_transition()
	await get_tree().create_timer(2)

	await _show_dialogue([
		"Well, your brain is still uncooked. That's a start.",
		"Well, let's see what this thing can do. Once I'm in relay range, activate the null spike... and then clear me a path.",
		"You've got this kid. I picked you for a reason."
	], "", Rect2(), _center_dialogue_pos(), true)
	_set_objective("- Wait for Blackjack to get within range of the drones")
	_release_runner_hold("pre_gauntlet_02")

func _run_gauntlet_sequence():
	await _wait_for_cell(59.5)
	_acquire_runner_hold("pre_gauntlet_03")
	_show_dialogue([
		"This is it. Cross your fingers and hit the Spike.\nReady when you are."
	], "", Rect2(), _center_dialogue_pos(), true)
	_set_objective("- Press Left Shift to activate the Null Spike
- Use your tools to help Blackjack get past the drones
- RUN sniff or RUN decrypt to access locked signals
- KILL exposed signals to disable them
- Watch out for Reboot and other ICE!")
	
	_enable_feature("null_spike", true)
	await GlobalEvents.activate_first_null_spike
	# disable null spike while running sync sequence
	_release_runner_hold("pre_gauntlet_03")

	await null_spike_sync_sequence()
	_enable_feature("null_spike", false)

	await _wait_for_cell(68.5)

	#NOTE: Logic for auto-dismissing during this sequence is in dialogue_window.set_text
	_show_dialogue([
		"H  o  l  y\n    s  h  i  t  .  .  ."
	], "", Rect2(), Vector2(50,300), true)

	await _wait_for_cell(70.5)

	_show_dialogue([
		"Y  o  u  '  r  e\n    a  c  t  u  a  l  l  y\n    d  o  i  n  g    i  t  .  .  ."
	],  "", Rect2(), Vector2(50,300), true)

	await _wait_for_cell(73)
	window_manager.objective_tracker.hide()
	
	_acquire_runner_hold("end")

	_show_dialogue([
		"I  '  m    h  e  r  e  .  .  .\nY  o  u    n  e  e  d    t  o\nd  i  s  c  o  n  n  e  c  t"
	],  "", Rect2(), Vector2(50,300), true, -1, "", 3)

	await get_tree().create_timer(2).timeout
	
	_show_dialogue([
		"K  i  d  !  ?  .  .  .\n  D  i  s  c  o  n  n  e  c  t  !"
	],  "", Rect2(), Vector2(50,300), true)

	await get_tree().create_timer(3).timeout

	signal_manager.hide_signals()
	timeline_manager.toggle_null_spike()
	await cutscene_controller.play_reverse_glitch_transition(2.0)
	await get_tree().create_timer(.5).timeout

	get_tree().change_scene_to_file("res://Scenes/end_screen.tscn")


# "BEFORE THE ghosts clipped off and left us to drift in the world they built for us."


func null_spike_sync_sequence():
	# clear remaining dialogue window if necessary
	var window = window_manager.find_child("DialogueWindow", true, false)
	if window != null:
		window.queue_free()

	_enable_feature("scan", false)
	Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)

	var sync_text := FileAccess.get_file_as_string(NULL_SPIKE_SYNC_PATH)
	var sync_duration = terminal_window.estimate_type_duration(sync_text, 0.02)
	print(sync_duration)
	cutscene_controller.start_first_null_spike_sync(sync_duration)
	await terminal_window.play_null_spike_sync(sync_text, 0.02)
	await cutscene_controller.null_spike_sync_finished
#	NOTE: Be careful if we change timings
	GlobalEvents.first_null_spike = false
	timeline_manager.toggle_null_spike()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	_enable_feature("scan", true)


func _prepare_debug_stage_door_01() -> void:
	_set_cutscene_black_screen(false)
	window_manager.auto_focus_puzzles = true
	_set_runner_cell(5.2)
	_mark_signal_scanned("cam_01")
	_mark_signal_disabled("cam_01")
	_enable_feature("scan")
	_enable_feature("connect")
	_enable_feature("terminal_commands")
	_enable_feature("null_spike", false)
	_set_objective("")

func _prepare_debug_stage_cam_02() -> void:
	_set_cutscene_black_screen(false)
	window_manager.auto_focus_puzzles = true
	_set_runner_cell(9.2)
	_mark_signal_scanned("cam_01")
	_mark_signal_disabled("cam_01")
	_mark_signal_scanned("door_01")
	_mark_door_unlocked("door_01")
	_enable_feature("scan")
	_enable_feature("connect")
	_enable_feature("terminal_commands")
	_enable_feature("null_spike", false)
	_set_objective("")

func _prepare_debug_stage_drone_01() -> void:
	_set_cutscene_black_screen(false)
	window_manager.auto_focus_puzzles = true
	_set_runner_cell(12)
	_enable_feature("scan")
	_enable_feature("connect")
	_enable_feature("terminal_commands")
	_enable_feature("null_spike", false)

func _prepare_debug_stage_null_door() -> void:
	_set_cutscene_black_screen(false)
	window_manager.auto_focus_puzzles = false
	_set_runner_cell(37.9)
	_enable_feature("scan")
	_enable_feature("connect")
	_enable_feature("terminal_commands")

func _prepare_debug_stage_lab_reveal() -> void:
	signal_manager.hide_signals()
	_set_cutscene_black_screen(false)
	window_manager.auto_focus_puzzles = false
	_set_runner_cell(45.9)
	_mark_signal_scanned("lab_door")
	_mark_door_unlocked("lab_door")
	_enable_feature("scan")
	_enable_feature("connect")
	_enable_feature("terminal_commands")
	_enable_feature("null_spike", false)
	_set_objective("")

func _prepare_debug_stage_terminal_dump() -> void:
	signal_manager.hide_signals()
	_set_cutscene_black_screen(false)
	window_manager.auto_focus_puzzles = false
	_set_runner_cell(46.0)
	_acquire_runner_hold("null_terminal_gate_02")
	_mark_signal_scanned("lab_door")
	_mark_door_unlocked("lab_door")
	_mark_signal_scanned("null_terminal")
	_unlock_signal_puzzle("null_terminal")
	_enable_feature("scan")
	_enable_feature("connect")
	_enable_feature("terminal_commands")
	_enable_feature("null_spike", false)
	_set_objective("")
	terminal_window.z_index = 100
	terminal_window.switch_session(_get_active_signal("null_terminal"))
	cutscene_controller.play_still_reveal(0.01)

func _prepare_debug_stage_alarm() -> void:
	signal_manager.hide_signals()
	window_manager.auto_focus_puzzles = false
	_prepare_debug_stage_terminal_dump()
	terminal_window.clear_log()
	terminal_window.z_index = 0

func _prepare_debug_pre_gauntlet() -> void:
	# NOTE: Make sure there's no weird floating texture changes
	window_manager.auto_focus_puzzles = false
	cutscene_controller.hide()
	_enable_feature("scan")
	_enable_feature("connect")
	_enable_feature("terminal_commands")
	_enable_feature("null_spike", false)
	_get_active_signal("c_drone_01").disable_signal()

	# speed up gauntlet drones
	for sig in signal_manager.signal_queue:
		if sig.data.display_name.contains("c_drone"):
			sig.data.detection.turn_speed_deg_per_sec = 270.0
	_set_runner_cell(55.9)

func _prepare_debug_gauntlet() -> void:
	_prepare_debug_pre_gauntlet()

	_set_runner_cell(59.0)
	
func _set_cutscene_black_screen(enabled: bool) -> void:
	if cutscene_controller == null:
		return
	cutscene_controller.set_black_screen(enabled)

func _start_cutscene_alarm() -> void:
	if cutscene_controller == null:
		return
	cutscene_controller.start_alarm_effects()

func _stop_cutscene_alarm(fade_duration: float = 0.35) -> void:
	if cutscene_controller == null:
		return
	await cutscene_controller.stop_alarm_effects(fade_duration)

# Free-floating dialogue position. The old timeline strip left empty space
# under it; the facility map fills that space, so during gameplay in map mode
# the dialogue docks to the right of the terminal instead. Cutscenes (signals
# hidden) keep the centered position.
func _center_dialogue_pos() -> Vector2:
	if timeline_manager != null and timeline_manager.map_mode and signal_manager.visible:
		return Vector2(1490, 630)
	return Vector2(750, 300)

func _set_runner_cell(cell_pos: float) -> void:
	if timeline_manager == null:
		return
	timeline_manager.current_cell_pos = cell_pos
	timeline_manager.current_cell = floor(cell_pos) as int
	timeline_manager.last_emitted_cell = timeline_manager.current_cell

func _mark_signal_scanned(system_id: String) -> void:
	var active_sig := _get_active_signal(system_id)
	if active_sig == null:
		return
	if active_sig.scan_layers.is_empty():
		active_sig.generate_scan_layers()
	active_sig.current_scan_index = active_sig.scan_layers.size()
	active_sig.current_layer_progress = 0.0
	active_sig.is_being_scanned = false
	if active_sig.instance_node != null:
		active_sig.instance_node.update_visuals()

func _mark_signal_disabled(system_id: String) -> void:
	var active_sig := _get_active_signal(system_id)
	if active_sig == null or active_sig.is_disabled:
		return
	active_sig.disable_signal()

func _mark_door_unlocked(system_id: String) -> void:
	var active_sig := _get_active_signal(system_id)
	if active_sig == null or active_sig.data == null:
		return
	active_sig.set_door_locked(false)

func _unlock_signal_puzzle(system_id: String) -> void:
	var active_sig := _get_active_signal(system_id)
	if active_sig == null or active_sig.data == null or active_sig.data.puzzle == null:
		return
	active_sig.data.puzzle.puzzle_locked = false

func _run_terminal_dump_sequence() -> void:
	if terminal_window == null:
		return
	var dump_text := FileAccess.get_file_as_string(NULL_SPIKE_DUMP_PATH)
	if dump_text.is_empty():
		return
	await terminal_window.play_system_dump(dump_text)

func _focus_runner() -> void:
	if runner_focus_panel == null:
		window_manager.clear_focus_overlay()
		return
	window_manager.focus_control(runner_focus_panel)

func _focus_heat_tracker() -> void:
	if heat_tracker == null:
		window_manager.clear_focus_overlay()
		return
	window_manager.focus_control(heat_tracker, Vector2(24, 24))

func _focus_door_lock_state(system_id: String) -> void:
	print("is _focus_door_lock_state doing anything?")
	var active_sig := _get_active_signal(system_id)
	if active_sig == null or active_sig.instance_node == null:
		window_manager.clear_focus_overlay()
		return
	var lock_rect = active_sig.instance_node.tooltip_main.get_lock_state_focus_rect()
	if not _has_focus_rect(lock_rect):
		window_manager.focus_signal(active_sig)
		return
	window_manager.focus_rect(lock_rect, Vector2(16, 16))

func _show_dialogue(
	dialogue_pages: Array[String],
	signal_id: String = "",
	focus_rect: Rect2 = Rect2(),
	default_position: Vector2 = Vector2(),
	has_custom_position: bool = false,
	stop_cell_if_open: float = -1,
	stop_hold_key: String = "",
	auto_dismiss: int = 0
) -> void:
	var resolved_focus_rect := _apply_focus(signal_id, focus_rect)
	# On the facility map, targets sit mid-screen and often move, so anchoring
	# the dialogue next to them covers the action. Dock it instead; the focus
	# overlay still points at the target.
	if timeline_manager.map_mode and not has_custom_position:
		default_position = _center_dialogue_pos()
		has_custom_position = true
	GlobalEvents.tutorial_lock_changed.emit(true)
	var dialogue = window_manager.show_tutorial_dialogue(
		dialogue_pages,
		resolved_focus_rect,
		default_position,
		has_custom_position
	)
	if stop_cell_if_open >= 0:
		_hold_at_cell_until_dialogue_finishes(dialogue, stop_cell_if_open, stop_hold_key)
	if auto_dismiss > 0:
		await get_tree().create_timer(auto_dismiss).timeout
		if dialogue != null:
			dialogue.dismissed.emit()
			dialogue.queue_free()
	else:
		await dialogue.dismissed

func _apply_focus(signal_id: String = "", custom_focus_rect: Rect2 = Rect2()) -> Rect2:
	if _has_focus_rect(custom_focus_rect):
		window_manager.focus_rect(custom_focus_rect)
		return custom_focus_rect

	if signal_id.is_empty():
		window_manager.clear_focus_overlay()
		return Rect2()

	var active_sig := _get_active_signal(signal_id)
	if active_sig == null:
		window_manager.clear_focus_overlay()
		return Rect2()
	if active_sig.instance_node == null:
		window_manager.clear_focus_overlay()
		return Rect2()

	var resolved_focus_rect = active_sig.instance_node.get_focus_rect()
	if not _has_focus_rect(resolved_focus_rect):
		window_manager.clear_focus_overlay()
		return Rect2()

	window_manager.focus_signal(active_sig)
	return resolved_focus_rect

func _hold_at_cell_until_dialogue_finishes(dialogue: Control, stop_cell: int, hold_key: String) -> void:
	if dialogue == null or not is_instance_valid(dialogue):
		return
	await _wait_for_cell(stop_cell)
	if dialogue == null or not is_instance_valid(dialogue):
		return
	var resolved_hold_key := hold_key if not hold_key.is_empty() else "dialogue_stop_%s" % stop_cell
	_acquire_runner_hold(resolved_hold_key)
	await dialogue.dismissed
	_release_runner_hold(resolved_hold_key)

func _wait_for_cell(target_cell: int) -> void:
	while timeline_manager.current_cell < target_cell:
		var args: Array = await _await_signal_args(GlobalEvents.cell_reached)
		if not args.is_empty() and int(args[0]) >= target_cell:
			return

func _wait_for_scan_complete(system_id: String) -> void:
	var active_sig := _get_active_signal(system_id)
	if active_sig != null and active_sig.current_scan_index >= active_sig.scan_layers.size():
		return
	while true:
		var args: Array = await _await_signal_args(GlobalEvents.signal_scan_complete)
		var signal_data: SignalData = null
		if not args.is_empty():
			signal_data = args[0] as SignalData
		if signal_data != null and signal_data.system_id == system_id:
			return

func _wait_for_signal_connect(system_id: String) -> void:
	var active_sig := _get_active_signal(system_id)
	if active_sig != null and active_sig.terminal_session != null and active_sig.terminal_session.has_tab:
		return
	while true:
		var args: Array = await _await_signal_args(GlobalEvents.signal_connect)
		var signal_data: SignalData = null
		if not args.is_empty():
			signal_data = args[0] as SignalData
		if signal_data != null and signal_data.system_id == system_id:
			return

func _wait_for_signal_killed(system_id: String) -> void:
	var active_sig := _get_active_signal(system_id)
	if active_sig != null and active_sig.is_disabled:
		return
	while true:
		var args: Array = await _await_signal_args(GlobalEvents.signal_killed)
		if not args.is_empty():
			active_sig = args[0] as ActiveSignal
		if active_sig != null and active_sig.data != null and active_sig.data.system_id == system_id:
			return

func _wait_for_puzzle_started(puzzle_type: PuzzleComponent.Type) -> void:
	while true:
		var args: Array = await _await_signal_args(GlobalEvents.puzzle_started)
		if args.size() < 2:
			continue
		if int(args[1]) == int(puzzle_type):
			return

func _wait_for_puzzle_solved(system_id: String) -> void:
	var active_sig := _get_active_signal(system_id)
	if active_sig != null and active_sig.data != null and active_sig.data.puzzle != null and not active_sig.data.puzzle.puzzle_locked:
		return
	while true:
		var args: Array = await _await_signal_args(GlobalEvents.puzzle_solved)
		var signal_data: SignalData = null
		if not args.is_empty():
			signal_data = args[0] as SignalData
		if signal_data != null and signal_data.system_id == system_id:
			return

func _wait_for_door_unlocked(system_id: String) -> void:
	while true:
		var active_sig := _get_active_signal(system_id)
		if active_sig != null and active_sig.data != null and not active_sig.data.door_locked:
			return
		await get_tree().process_frame

func _cam_02_kill_or_hustle(active_signal: ActiveSignal) -> String:
	var resolved := false
	
	var on_move = func():
		if resolved:
			return
		resolved = true
		print("returning on move")
		wait_completed.emit("move")
	
	var on_kill = func(active_signal: ActiveSignal):
		if resolved:
			return
		if active_signal.data.system_id != "cam_02":
			return
		resolved = true
		print("returning on kill")
		wait_completed.emit("kill")

	GlobalEvents.runner_hustle.connect(on_move, CONNECT_ONE_SHOT)
	GlobalEvents.signal_killed.connect(on_kill)
	
	print("awaiting")
	var result = await wait_completed
	
	if GlobalEvents.signal_killed.is_connected(on_kill):
		GlobalEvents.signal_killed.disconnect(on_kill)
	print("returning for real")
	return result

func _runner_detected_dialogue():
	# NOTE: Might need to add cell gating here to keep this from firing later
	if timeline_manager.current_cell_pos > 41: return
	_show_dialogue([
		"Agh, it pinged me. Shouldn't be a problem. Quick glances don't build much heat."
		], "", Rect2(), _center_dialogue_pos(), true, -1, "", 3
	)

func _await_signal_args(signal_to_wait: Signal) -> Array:
	var result = await signal_to_wait
	if result is Array:
		return result
	return [result]

func _get_active_signal(system_id: String) -> ActiveSignal:
	if signal_manager == null:
		return null
	return signal_manager.get_signal_by_system_id(system_id)

func _has_focus_rect(focus_rect: Rect2) -> bool:
	return focus_rect.size.x > 0.0 and focus_rect.size.y > 0.0

func _set_objective(text: String) -> void:
	if text.is_empty():
		window_manager.clear_tutorial_objective()
		return
	window_manager.set_tutorial_objective(text)

func _disable_tutorial_features() -> void:
	_enable_feature("scan", false)
	_enable_feature("connect", false)
	_enable_feature("terminal_commands", false)
	_enable_feature("null_spike", false)

func _enable_feature(feature_key: String, enabled: bool = true) -> void:
	print("Changed: ", feature_key, enabled)
	GlobalEvents.set_tutorial_feature_enabled(feature_key, enabled)

func _acquire_runner_hold(hold_key: String) -> void:
	if hold_key.is_empty():
		return
	if _active_runner_hold_tokens.has(hold_key):
		return
	_active_runner_hold_tokens[hold_key] = GlobalEvents.acquire_runner_hold("tutorial_%s" % hold_key)

func _release_runner_hold(hold_key: String) -> void:
	if hold_key.is_empty():
		return
	if not _active_runner_hold_tokens.has(hold_key):
		return
	var token: String = _active_runner_hold_tokens[hold_key]
	_active_runner_hold_tokens.erase(hold_key)
	GlobalEvents.release_runner_hold(token)
