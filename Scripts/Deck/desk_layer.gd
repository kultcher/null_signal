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
@export var deck_chassis_origin := Vector2(30, 640)
## Aux module chassis top-left positions, in order of preference.
@export var aux_docks: Array[Vector2] = [Vector2(1436, 520), Vector2(880, 190), Vector2(380, 190)]
## Optional: an existing TerminalWindow to move onto the deck screen at startup.
@export var terminal_path: NodePath
@export var hide_terminal_detail_row := true

var root: Control
var deck: MainDeck
var cable: DeckCable
var aux_root: Control
var _aux: Array[DeviceShell] = []


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

	if not terminal_path.is_empty():
		var term := get_node_or_null(terminal_path) as Control
		if term != null:
			adopt_terminal.call_deferred(term)


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
