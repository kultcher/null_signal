extends Node
## A standalone lab so encounter-gauntlet development can continue independently.

@export var lag: LagModule = LagModule.new()
@export var spammer: SpammerModule = SpammerModule.new()
@export var degrade: DegradeModule = DegradeModule.new()
@export var blackout: BlackoutModule = BlackoutModule.new()
@export var glitch: GlitchModule = GlitchModule.new()
@export var redact: RedactModule = RedactModule.new()
@export var selected_effects := PackedStringArray(["lag"])
@export var include_callback := false
@export_enum("none", "decrypt", "sniff", "fuzz") var puzzle_type := "none"
@export_range(1, 5, 1) var puzzle_difficulty := 2

@onready var game = $Game
var settings_panel: PanelContainer
var status: Label
var selections: Dictionary = {}
var current: ActiveSignal
var serial := 0
var running := false

func _enter_tree() -> void:
	$Game/RunManager.level_script_path = "res://Resources/RunData/AuthoredRuns/DisruptionTestRun.gd"
	$Game/RunManager.debug_free_play = true
	$Game/WindowManager.game_over_on_runner_death = false
	$Game/LevelViewer.process_mode = Node.PROCESS_MODE_DISABLED
	$Game/SignalTimeline.position.y = 110
	$Game/SignalTimeline/TimelineManager.map_height_px = 460

func _ready() -> void:
	game.get_node("WindowManager").auto_focus_puzzles = false
	game.get_node("TempQuitButton").hide()
	CommandDispatch.timeline_manager.BASE_CELLS_PER_SECOND = 0.0
	CommandDispatch.timeline_manager.cells_per_second = 0.0
	_build_ui()
	# Let the initial terminal handshake finish before replacing its context.
	await get_tree().create_timer(1.1).timeout
	fresh_host()

func _process(_delta: float) -> void:
	if status == null:
		return
	var name := current.data.system_id if current != null else "none"
	var connected := current != null and current.terminal_session != null and current.terminal_session.has_tab
	status.text = "DISRUPTIVE IC LAB // %s // %s\nChoose IC and tuning, then Apply. Solid cyan pip = real Glitch; hollow pip = echo." % [name, "CONNECTED" if connected else "DISCONNECTED"]

func _build_ui() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 25
	add_child(hud)
	var bar := PanelContainer.new()
	var theme := Theme.new()
	theme.default_font = preload("res://Visuals/Fonts/ShareTechMono-Regular.ttf")
	theme.default_font_size = 18
	bar.theme = theme
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.015, 0.03, 0.038, 0.97)
	panel_style.border_color = Color(0.08, 0.65, 0.7)
	panel_style.set_border_width_all(1)
	panel_style.set_content_margin_all(12)
	bar.add_theme_stylebox_override("panel", panel_style)
	bar.position = Vector2(16, 8)
	bar.size = Vector2(1888, 90)
	hud.add_child(bar)
	var rows := VBoxContainer.new()
	bar.add_child(rows)
	status = Label.new()
	rows.add_child(status)
	var actions := HBoxContainer.new()
	rows.add_child(actions)
	_button(actions, "Tuning", func(): settings_panel.visible = not settings_panel.visible)
	_button(actions, "Apply / fresh host", fresh_host)
	_button(actions, "Connect host", func():
		if current != null:
			CommandDispatch.process_command("ACCESS " + current.data.system_id, CommandDispatch.terminal_window.active_signal)
	)
	_button(actions, "Disconnect host", func():
		if current != null and current.terminal_session != null:
			CommandDispatch.terminal_window._close_session_tab(current.terminal_session, current)
	)
	_button(actions, "Root tab", func(): CommandDispatch.terminal_window.restore_session(CommandDispatch.terminal_window.root_session))
	_button(actions, "Runner: move / stop", func():
		running = not running
		CommandDispatch.timeline_manager.BASE_CELLS_PER_SECOND = 0.15 if running else 0.0
		CommandDispatch.timeline_manager.cells_per_second = 0.15 if running else 0.0
	)
	settings_panel = PanelContainer.new()
	settings_panel.theme = theme
	settings_panel.add_theme_stylebox_override("panel", panel_style)
	settings_panel.position = Vector2(16, 112)
	settings_panel.size = Vector2(430, 922)
	hud.add_child(settings_panel)
	var scroll := ScrollContainer.new()
	settings_panel.add_child(scroll)
	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation", 6)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(options)
	var heading := Label.new()
	heading.text = "IC + TUNING"
	options.add_child(heading)
	for key in ["lag", "spammer", "degrade", "blackout", "glitch", "redact"]:
		var module: DisruptionModule = get(key)
		var enabled := CheckBox.new()
		enabled.text = key.capitalize()
		enabled.button_pressed = key in selected_effects
		options.add_child(enabled)
		selections[key] = enabled
		for knob in module.get_tuning_keys():
			_add_knob(options, module, knob)
	var callback := CheckBox.new()
	callback.text = "Include Callback"
	callback.button_pressed = include_callback
	callback.toggled.connect(func(value): include_callback = value)
	options.add_child(callback)
	var puzzle := OptionButton.new()
	for name in ["none", "decrypt", "sniff", "fuzz"]:
		puzzle.add_item("Puzzle: " + name)
	puzzle.select(["none", "decrypt", "sniff", "fuzz"].find(puzzle_type))
	puzzle.item_selected.connect(func(index): puzzle_type = ["none", "decrypt", "sniff", "fuzz"][index])
	options.add_child(puzzle)
	var difficulty := SpinBox.new()
	difficulty.prefix = "Puzzle tier "
	difficulty.min_value = 1
	difficulty.max_value = 5
	difficulty.value = puzzle_difficulty
	difficulty.value_changed.connect(func(value): puzzle_difficulty = int(value))
	options.add_child(difficulty)
	_button(options, "Apply / fresh host", fresh_host)
	var note := Label.new()
	note.text = "Changes apply to a fresh host.\nRunner starts stopped.\nOther tabs preserve ongoing effects."
	options.add_child(note)

func _button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)

func _add_knob(parent: Node, module: DisruptionModule, key: String) -> void:
	var value = module.get(key)
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = key.replace("_", " ")
	label.custom_minimum_size.x = 160
	row.add_child(label)
	if key == "placement":
		var placement := OptionButton.new()
		for name in ["Timeline", "Terminal", "Both"]:
			placement.add_item(name)
		placement.select(int(value))
		placement.item_selected.connect(func(index): module.set(key, index))
		row.add_child(placement)
	elif value is bool:
		var toggle := CheckBox.new()
		toggle.button_pressed = value
		toggle.toggled.connect(func(enabled): module.set(key, enabled))
		row.add_child(toggle)
	elif value is Vector2:
		for axis in range(2):
			var number := SpinBox.new()
			number.min_value = (220 if axis == 0 else 120) if key == "popup_size" else 32
			number.max_value = 500
			number.value = value[axis]
			number.custom_minimum_size.x = 70
			number.value_changed.connect(func(updated):
				var vector: Vector2 = module.get(key)
				vector[axis] = updated
				module.set(key, vector)
			)
			row.add_child(number)
	else:
		var number := SpinBox.new()
		number.min_value = 0.05
		number.max_value = 60
		number.step = 0.05
		# Use the resource's Inspector metadata so the in-game knob does not
		# silently acquire a different range when profiles evolve.
		for property in module.get_property_list():
			if property.name == key and property.hint == PROPERTY_HINT_RANGE:
				var limits: PackedStringArray = property.hint_string.split(",")
				if limits.size() >= 3:
					number.min_value = float(limits[0])
					number.max_value = float(limits[1])
					number.step = float(limits[2])
		number.value = value
		number.value_changed.connect(func(updated): module.set(key, int(updated) if value is int else updated))
		row.add_child(number)

func fresh_host() -> void:
	var manager = CommandDispatch.signal_manager
	var terminal = CommandDispatch.terminal_window
	for sig in manager.signal_queue.duplicate():
		game.get_node("WindowManager").close_puzzles_for_signal(sig, false)
		game.get_node("SignalTimeline/ScanController").notify_signal_despawned(sig)
		if sig.terminal_session != null:
			terminal._close_session_tab(sig.terminal_session, sig)
		sig.release_run_state()
		if sig.instance_node != null:
			sig.instance_node.queue_free()
	manager.signal_queue.clear()
	game.get_node("SignalTimeline/GridLayer/RunnerTeam/PanelContainer/RunnerHealth").reset_health()
	game.get_node("HeatManager").set_heat(0, "Lab reset")
	CommandDispatch.timeline_manager.set_runner_cell(0)
	serial += 1
	var definition := RunDefinition.new()
	var data := definition.BASIC_DOOR.duplicate(true) as SignalData
	data.system_id = "host_%d" % serial
	data.display_name = data.system_id
	data.ic_modules = ICComponent.new()
	data.set_meta("auto_codex_popups", false)
	for key in selections:
		if selections[key].button_pressed:
			var module := get(key).duplicate(true) as DisruptionModule
			module.set_custom_fixed()
			data.ic_modules.add_module(module)
	if include_callback:
		data.ic_modules.add_module(definition.build_ic("callback", 2))
	data.puzzle = definition.build_puzzle(puzzle_type, puzzle_difficulty) if puzzle_type != "none" else null
	manager.spawn_signal_data(data, 2.0)
	current = manager.signal_queue[-1]
	for cell in [1.0, 3.0]:
		var other := definition.BASIC_TERMINAL.duplicate(true) as SignalData
		other.system_id = "neighbor_%d_%d" % [serial, int(cell)]
		other.display_name = other.system_id
		other.lane = 4
		other.ic_modules = ICComponent.new()
		other.set_meta("auto_codex_popups", false)
		manager.spawn_signal_data(other, cell)
	manager.update_signal_position()
	# Reveal details in this lab, while retaining the game's actual scan model.
	for sig in manager.signal_queue:
		for layer in sig.scan_layers:
			layer.revealed = true
		sig.current_scan_index = sig.scan_layers.size()
		if sig.instance_node != null:
			sig.instance_node.rebuild_tooltip()
	terminal.restore_session(terminal.root_session)
	terminal.print_to_log("LAB: ACCESS %s, then try commands, switch tabs, or disconnect.\nUse OP to open the door after clearing any puzzle/Callback." % current.data.system_id)
