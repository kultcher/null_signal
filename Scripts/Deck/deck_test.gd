# deck_test.gd
# Standalone look-and-feel test for the hardware deck. Run Scenes/Deck/deck_test.tscn (F6).
#
#   F2  plug in the decrypt module (real decrypt puzzle)
#   F3  plug in a second module running the sniff puzzle
#   F4  step the heat gauge
#   F5  cycle indicator lamp states
#   Esc unplug the newest module
#   Drag any bezel to pick a device up; double-click it to send it home.
#
# The terminal here is a stand-in that uses the game's MainTheme, so the line count on
# the status LCD matches what the real terminal would fit. Set use_real_terminal to try
# the actual TerminalWindow scene (it expects the run managers, so expect some errors).

extends Node

const MAIN_THEME := preload("res://Resources/StyleBox/MainTheme.tres")
const TERMINAL_SCENE := preload("res://Scenes/terminal_window.tscn")
const DECRYPT_SCENE := preload("res://Scenes/decrypt.tscn")
const SNIFF_SCENE := preload("res://Scenes/sniff.tscn")
const FONT := preload("res://Visuals/Fonts/KodeMono-Bold.ttf")

@export var use_real_terminal := false

var desk: DeskLayer
var history: RichTextLabel
var _heat_step := 0
var _lamp_step := 0
var _modules: Array[Control] = []
var _uptime := 0.0


func _ready() -> void:
	_build_backdrop()

	desk = DeskLayer.new()
	add_child(desk)
	await get_tree().process_frame

	if use_real_terminal:
		desk.adopt_terminal(TERMINAL_SCENE.instantiate())
	else:
		desk.deck.fill_content(_build_stand_in_terminal())

	desk.deck.set_cartridges(["SPOOF", "PROBE", "ICEPK", ""],
		[Color(0.95, 0.55, 0.25), Color(0.55, 0.8, 0.95), Color(0.85, 0.85, 0.8)])
	desk.deck.cartridge_pressed.connect(_on_cartridge_pressed)
	desk.deck.set_ram(3, 8)
	desk.deck.set_heat(0.2)
	desk.deck.set_lamp("scan", MainDeck.Lamp.ACTIVE, "SCAN 64%")
	desk.deck.set_lamp("lock", MainDeck.Lamp.WARN, "LOCKED")
	desk.deck.set_lamp("ic", MainDeck.Lamp.IDLE, "IC ?")
	desk.deck.set_lamp("aux", MainDeck.Lamp.OFF, "AUX")
	desk.aux_docked.connect(_on_aux_docked)
	desk.aux_removed.connect(_on_aux_removed)


func _on_cartridge_pressed(i: int) -> void:
	_log("[color=#7fbf8f]cartridge %d engaged[/color]" % i)


func _on_aux_docked(_shell: DeviceShell) -> void:
	desk.deck.set_lamp("aux", MainDeck.Lamp.ACTIVE, "AUX LINK")


func _on_aux_removed(_shell: DeviceShell) -> void:
	if desk.get_aux_shells().is_empty():
		desk.deck.set_lamp("aux", MainDeck.Lamp.OFF, "AUX")


func _process(delta: float) -> void:
	_uptime += delta
	if desk == null or desk.deck == null:
		return
	var lines := -1
	if history != null:
		lines = int(history.size.y / maxf(1.0, history.get_theme_font("normal_font").get_height(history.get_theme_font_size("normal_font_size"))))
	desk.deck.set_status("UPTIME %02d:%02d  |  %d LINES" % [floori(_uptime / 60.0), int(_uptime) % 60, lines])


func _input(event: InputEvent) -> void:
	# _input (not _unhandled_input) so the focused terminal LineEdit cannot swallow these
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var handled := true
	match event.keycode:
		KEY_F2:
			_plug(DECRYPT_SCENE.instantiate())
		KEY_F3:
			_plug(SNIFF_SCENE.instantiate())
		KEY_F4:
			_heat_step = (_heat_step + 1) % 6
			desk.deck.set_heat(_heat_step / 5.0)
		KEY_F5:
			_lamp_step = (_lamp_step + 1) % 5
			desk.deck.set_lamp("ic", _lamp_step as MainDeck.Lamp, ["IC OFF", "IC ?", "IC CLEAR", "IC: TRACE", "IC: ALERT"][_lamp_step])
		KEY_ESCAPE:
			if not _modules.is_empty():
				var m: Control = _modules.pop_back()
				if is_instance_valid(m):
					m.queue_free()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _plug(puzzle: Control) -> void:
	_modules.append(puzzle)
	if puzzle.has_signal("puzzle_solved"):
		puzzle.puzzle_solved.connect(_on_module_solved.bind(puzzle))
	desk.dock_content(puzzle, "aux_decrypt")
	_log("aux module attached on EXP-A")


func _on_module_solved(puzzle: Control) -> void:
	_log("[color=#7fff9f]module reports SOLVED[/color]")
	_modules.erase(puzzle)
	puzzle.queue_free()


func _log(bb: String) -> void:
	if history != null:
		history.append_text("\n" + bb)


# --- scene dressing ------------------------------------------------------------------

func _build_backdrop() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)

	var desk_bg := ColorRect.new()
	desk_bg.color = Color(0.035, 0.04, 0.038)
	desk_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	desk_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(desk_bg)

	# Where the facility map currently lives (TimelineBaseRect: y 43..343).
	var map := ColorRect.new()
	map.color = Color(0.02, 0.07, 0.07)
	map.position = Vector2(0, 43)
	map.size = Vector2(1920, 300)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(map)
	var map_label := Label.new()
	map_label.text = "FACILITY MAP AREA  (y 43-343)"
	map_label.position = Vector2(24, 60)
	map_label.add_theme_font_override("font", FONT)
	map_label.add_theme_font_size_override("font_size", 18)
	map_label.add_theme_color_override("font_color", Color(0.2, 0.55, 0.5))
	bg_layer.add_child(map_label)

	var help := Label.new()
	help.text = "F2 decrypt module   F3 sniff module   F4 heat   F5 IC lamp   Esc unplug   drag bezels / double-click = home"
	help.position = Vector2(24, 8)
	help.add_theme_font_override("font", FONT)
	help.add_theme_font_size_override("font_size", 16)
	help.add_theme_color_override("font_color", Color(0.5, 0.55, 0.5))
	bg_layer.add_child(help)


func _build_stand_in_terminal() -> Control:
	var term := VBoxContainer.new()
	term.name = "StandInTerminal"
	term.theme = MAIN_THEME
	term.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "DC_OS | [/cAl4x/pRk09s]    root   cam_01   door_02"
	title.custom_minimum_size = Vector2(0, 30)
	term.add_child(title)

	history = RichTextLabel.new()
	history.bbcode_enabled = true
	history.scroll_following = true
	history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history.text = "\n".join([
		"Routing through proxy chain ... 3 hops ... connected.....",
		"Connected.",
		"Enter command.",
		"> scan cam_01",
		"  [color=#7fbf8f]handshake: backdoor route[/color]",
		"  status: fallback node [online]",
		"  layer 1/3 .......... ok",
		"  layer 2/3 .......... ok",
		"  layer 3/3 .......... [color=#ffbf40]ICE DETECTED: tripwire[/color]",
		"> lock cam_01",
		"  [color=#ff6a50]LOCK REQUIRES KEY -- decrypt or sniff[/color]",
		"> help",
		"  scan <id>   lock <id>   null   spoof <id>   probe <id>",
	])
	term.add_child(history)

	var cmd := HBoxContainer.new()
	var prefix := Label.new()
	prefix.text = "-root-["
	cmd.add_child(prefix)
	var line := LineEdit.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.keep_editing_on_text_submit = true
	line.text_submitted.connect(_on_stand_in_submit.bind(line))
	cmd.add_child(line)
	term.add_child(cmd)
	line.call_deferred("grab_focus")
	return term


func _on_stand_in_submit(t: String, line: LineEdit) -> void:
	_log("> " + t)
	line.clear()
