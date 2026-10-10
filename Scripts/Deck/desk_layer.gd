# desk_layer.gd
# The physical desk: the main deck at the bottom of the screen, patch cables, and any
# hot-swapped aux modules (decrypt, sniff...) that are plugged in while a puzzle runs.
#
# Draw order (back to front): deck -> cables -> aux modules.
# Keep this layer BELOW WindowManager so tutorial focus/dialogue still draw on top.

class_name DeskLayer
extends CanvasLayer

signal aux_docked(shell: DeviceShell)
signal aux_removed(shell: DeviceShell)

@export var show_deck := true
## Where the deck chassis' top-left corner sits on screen.
@export var deck_chassis_origin := Vector2(210, 640)
## Aux module chassis top-left positions, in order of preference.
@export var aux_docks: Array[Vector2] = [Vector2(1316, 520), Vector2(720, 190), Vector2(200, 190)]
## Optional: an existing TerminalWindow to move onto the deck screen at startup.
@export var terminal_path: NodePath
@export var hide_terminal_detail_row := true

@export_group("Game wiring")
## HeatManager node (for max heat). Heat updates arrive via GlobalEvents.heat_state_changed.
@export var heat_manager_path: NodePath
## Old UI the deck replaces (e.g. HeatTracker, ProgramDock). Hidden while the desk is active.
@export var hide_when_active: Array[NodePath] = []
## ObjectiveTracker to show on the deck's secondary screen.
@export var objective_tracker_path: NodePath
## EscalationManager: re-laid out once the deck exists so its panel sits above the deck.
@export var escalation_manager_path: NodePath = ^"../EscalationManager"

var root: Control
var deck: MainDeck
var cable: DeckCable
var aux_root: Control
var _aux: Array[DeviceShell] = []
var terminal: Control
var _game_wired := false
var _heat_manager: Node
var _heat_ratio := 0.0
var _ram := Vector2i(0, 0)
var _toolbox: PanelContainer
var _time := 0.0
var _last_header := ""


func _ready() -> void:
	# Layer 0: draws above the main scene canvas, below WindowManager (layer 1). 2D lights
	# (screen spill, lamp glow) did not reach items on a non-zero CanvasLayer in testing.
	layer = 0
	root = Control.new()
	root.name = "DeskRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var deck_root := Control.new()
	deck_root.name = "DeckRoot"
	deck_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(deck_root)

	cable = DeckCable.new()
	cable.name = "Cables"
	root.add_child(cable)

	aux_root = Control.new()
	aux_root.name = "AuxRoot"
	aux_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(aux_root)

	if show_deck:
		deck = MainDeck.new()
		deck.name = "MainDeck"
		deck_root.add_child(deck)
		deck.position = deck_chassis_origin - deck.get_chassis_rect().position
		deck.home_position = deck.position
		deck.snap_points.append(deck.position)

	aux_docked.connect(_on_aux_count_changed)
	aux_removed.connect(_on_aux_count_changed)
	if not terminal_path.is_empty():
		_wire_game.call_deferred()


## Move a TerminalWindow onto the deck's main screen.
func adopt_terminal(term: Control) -> void:
	if deck == null or term == null:
		return
	deck.fill_content(term)
	term.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var inner := term.get_node_or_null("TerminalInner") as Control
	if inner != null:
		inner.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	if hide_terminal_detail_row:
		var detail := term.get_node_or_null("TerminalInner/TerminalVBox/SignalDetailHBox") as Control
		if detail != null:
			detail.visible = false


## Plug a Control (e.g. a puzzle window) into a new aux module. The module frees itself
## (with a power-down + slide-out) when the content leaves the tree.
func dock_content(content: Control, device_id := "aux_decrypt") -> DeviceShell:
	var shell := DeviceShell.new()
	shell.name = "Aux_%s" % device_id
	shell.device_id = device_id
	aux_root.add_child(shell)

	var chassis_offset := shell.get_chassis_rect().position
	var dock := _free_dock() - chassis_offset
	shell.home_position = dock
	for p in aux_docks:
		shell.snap_points.append(p - chassis_offset)

	shell.set_content(content)
	var decal_path := "res://Visuals/Deck/Decals/skull.png"
	if device_id == "aux_decrypt" and ResourceLoader.exists(decal_path):
		shell.add_decal(load(decal_path), Vector2(395, 435), 0.3, -8.0)
	content.tree_exiting.connect(_on_content_exiting.bind(shell), CONNECT_ONE_SHOT)

	if deck != null:
		cable.add_link(shell, "cable_port", Vector2.LEFT, deck, "exp_port_a", Vector2.UP)
	_aux.append(shell)
	_animate_in(shell, dock)
	aux_docked.emit(shell)
	return shell


## Screen y of the top of the deck's silhouette (ports and fins included), for laying out
## things that must stay visible above it.
func get_deck_top_y() -> float:
	if deck == null:
		return INF
	return deck.global_position.y + deck.get_chassis_rect().position.y - 20.0


func get_aux_shells() -> Array[DeviceShell]:
	return _aux


func _free_dock() -> Vector2:
	for p in aux_docks:
		var taken := false
		for s in _aux:
			if is_instance_valid(s) and s.home_position + s.get_chassis_rect().position == p:
				taken = true
				break
		if not taken:
			return p
	return aux_docks[aux_docks.size() - 1] + Vector2(30, 30) * _aux.size()


func _animate_in(shell: DeviceShell, dock: Vector2) -> void:
	shell.position = dock + Vector2(0, 260)
	shell.modulate.a = 0.0
	shell.scale = Vector2(0.97, 0.97)
	var t := shell.create_tween().set_parallel(true)
	t.tween_property(shell, "position", dock, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(shell, "modulate:a", 1.0, 0.15)
	t.tween_property(shell, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_callback(shell.power_on)


func _on_content_exiting(shell: DeviceShell) -> void:
	if not is_instance_valid(shell) or shell.is_queued_for_deletion() or not shell.is_inside_tree() or not is_inside_tree():
		return
	_aux.erase(shell)
	shell.draggable = false
	var t := shell.power_off()
	t.tween_interval(0.05)
	t.tween_property(shell, "position:y", shell.position.y + 260.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(shell, "modulate:a", 0.0, 0.3).set_delay(0.1)
	t.tween_callback(func():
		cable.remove_links_for(shell)
		aux_removed.emit(shell)
		shell.queue_free())


func _on_aux_count_changed(_shell: DeviceShell) -> void:
	if deck == null:
		return
	if _aux.is_empty():
		deck.set_lamp("aux", MainDeck.Lamp.OFF, "AUX")
	else:
		deck.set_lamp("aux", MainDeck.Lamp.ACTIVE, "AUX LINK" if _aux.size() == 1 else "AUX x%d" % _aux.size())


# --- game wiring -------------------------------------------------------------------------
# Autoloads are looked up by path so this script also runs in projects/scenes without them.

func _wire_game() -> void:
	if deck == null:
		return
	terminal = get_node_or_null(terminal_path) as Control
	if terminal != null:
		adopt_terminal(terminal)
		if terminal.has_signal("detail_panel_refreshed"):
			terminal.detail_panel_refreshed.connect(_sync_lamps)
		_sync_lamps()

	_heat_manager = get_node_or_null(heat_manager_path)
	var ge := get_node_or_null("/root/GlobalEvents")
	if ge != null and ge.has_signal("heat_state_changed"):
		ge.heat_state_changed.connect(_on_heat_state_changed)
	if _heat_manager != null and _heat_manager.has_method("get_heat"):
		_on_heat_state_changed(_heat_manager.get_heat(), "")

	var ram := get_node_or_null("/root/RAMManager")
	if ram != null:
		ram.ram_usage_changed.connect(_on_ram_usage_changed)
		_on_ram_usage_changed(ram.get_used_ram(), ram.total_ram)

	deck.program_cartridge_pressed.connect(_on_program_cartridge_pressed)
	deck.lamp_pressed.connect(_on_lamp_pressed)

	for path in hide_when_active:
		var n := get_node_or_null(path)
		if n is CanvasItem:
			n.visible = false
	var tracker := get_node_or_null(objective_tracker_path) as Control
	if tracker != null:
		deck.host_panel(tracker, "screen2")

	deck.set_lamp("aux", MainDeck.Lamp.OFF, "AUX")
	_game_wired = true
	var esc := get_node_or_null(escalation_manager_path)
	if esc != null and esc.has_method("_refresh_anchor_layout"):
		esc._refresh_anchor_layout()
		if esc.has_method("_refresh_signal_layout"):
			esc._refresh_signal_layout()


func _process(delta: float) -> void:
	_time += delta
	if not _game_wired or deck == null:
		return
	_sync_programs()
	if terminal != null and terminal.get("title_text") != null:
		var header: String = terminal.title_text.get_parsed_text()
		if header != _last_header:
			_last_header = header
			deck.set_header(header)


## Mirror the terminal's Scan / Lock / IC detail panels onto the deck's lamps.
func _sync_lamps() -> void:
	if terminal == null or deck == null:
		return
	var t = terminal
	if t.get("scan_label") == null:
		return
	deck.set_lamp_color("scan", t.scan_label.self_modulate, t.scan_label.text, _ratio(t.scan_progress))
	deck.set_lamp_color("lock", t.lock_label.self_modulate, t.lock_label.text)
	deck.set_lamp_color("ic", t.ic_label.self_modulate, t.ic_label.text, _ratio(t.ic_progress))
	var lock_actionable: bool = t.toolbox_button != null and not t.toolbox_button.disabled
	deck.set_lamp_clickable("lock", lock_actionable)
	if not lock_actionable:
		_close_toolbox()


func _ratio(bar: Range) -> float:
	if bar == null or bar.max_value <= bar.min_value:
		return -1.0
	return (bar.value - bar.min_value) / (bar.max_value - bar.min_value)


func _on_heat_state_changed(amount: float, _source) -> void:
	var max_heat := 1.0
	if _heat_manager != null and _heat_manager.has_method("get_max_heat"):
		max_heat = maxf(0.001, _heat_manager.get_max_heat())
	_heat_ratio = clampf(amount / max_heat, 0.0, 1.0)
	deck.set_heat(_heat_ratio)
	_update_status()


func _on_ram_usage_changed(used: int, total: int) -> void:
	_ram = Vector2i(used, total)
	deck.set_ram(used, total)
	_update_status()


func _update_status() -> void:
	deck.set_status("HEAT %3d%%   |   RAM %d/%d" % [roundi(_heat_ratio * 100.0), _ram.x, _ram.y])


# --- programs -> cartridges ---------------------------------------------------------------

func _sync_programs() -> void:
	var pm := get_node_or_null("/root/ProgramManager")
	if pm == null:
		return
	var list: Array = []
	for p in pm.get_programs():
		var d = p.definition
		list.append({
			"id": p.get_program_id(),
			"name": p.get_display_name(),
			"description": p.get_description(),
			"icon": d.icon if d != null else null,
			"state": int(p.state),
			"progress": _program_progress(p),
		})
	deck.sync_programs(list, _time)


func _program_progress(p) -> float:
	var d = p.definition
	if d == null:
		return 1.0
	match int(p.state):
		MainDeck.ProgState.LOADING:
			return 1.0 if d.load_time_sec <= 0.0 else clampf(1.0 - p.time_remaining_sec / d.load_time_sec, 0.0, 1.0)
		MainDeck.ProgState.CLEANUP:
			var total: float = d.cleanup_time_sec if p.was_used else d.get_cancel_cleanup_time_sec()
			return 0.0 if total <= 0.0 else clampf(p.time_remaining_sec / total, 0.0, 1.0)
		MainDeck.ProgState.RUNNING:
			return 1.0
	return 0.0


## Same rules as the old ProgramDock: left click loads a docked program or fires a running
## manual one; right click ejects.
func _on_program_cartridge_pressed(program_id: StringName, button: int) -> void:
	var pm := get_node_or_null("/root/ProgramManager")
	if pm == null:
		return
	var p = pm.get_program(program_id)
	if p == null:
		return
	if button == MOUSE_BUTTON_RIGHT:
		pm.request_unload(program_id)
		return
	match int(p.state):
		MainDeck.ProgState.DOCKED:
			pm.request_load(program_id)
		MainDeck.ProgState.RUNNING:
			var d = p.definition
			if d != null and not d.is_passive() and d.is_manual_activation():
				pm.request_use(program_id)


# --- lock lamp -> sniff / decrypt flyout ----------------------------------------------------

func _on_lamp_pressed(key: String) -> void:
	if key == "lamp_lock":
		if _toolbox != null and is_instance_valid(_toolbox):
			_close_toolbox()
		else:
			_open_toolbox()


func _open_toolbox() -> void:
	if terminal == null:
		return
	_toolbox = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.035, 0.95)
	style.border_color = Color(0.4, 0.9, 0.55, 0.8)
	style.set_border_width_all(2)
	style.set_content_margin_all(6)
	_toolbox.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_toolbox.add_child(row)
	for entry in [["SNIFF", "_on_sniff_button_pressed"], ["DECRYPT", "_on_decrypt_button_pressed"]]:
		var b := Button.new()
		b.text = entry[0]
		b.add_theme_font_override("font", MainDeck.FONT)
		b.add_theme_font_size_override("font_size", 18)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_toolbox_choice.bind(entry[1]))
		row.add_child(b)
	root.add_child(_toolbox)
	var lamp := deck.get_lamp_global_rect("lock")
	_toolbox.position = Vector2(lamp.end.x + 8, lamp.position.y + 4)


func _on_toolbox_choice(method: String) -> void:
	_close_toolbox()
	if terminal != null and terminal.has_method(method):
		terminal.call(method)


func _close_toolbox() -> void:
	if _toolbox != null and is_instance_valid(_toolbox):
		_toolbox.queue_free()
	_toolbox = null
