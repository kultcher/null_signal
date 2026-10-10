class_name FuzzPuzzle extends PanelContainer

signal puzzle_solved
signal puzzle_failed

@export var puzzle_config: FuzzPuzzleConfig
var linked_signal: ActiveSignal
var state := FuzzPuzzleState.new()
var aim_angle := -PI * 0.5
var impacts: Array[Dictionary] = []
var show_sweet_spot := false # Test harness only; never shown in gameplay.
var _solved_emitted := false
var _dragging := false
var _drag_offset := Vector2.ZERO

@onready var arena: Control = $Layout/Arena
@onready var progress_bar: ProgressBar = $Layout/Progress
@onready var readout: Label = $Layout/Readout
@onready var focus_label: Label = $Layout/Focus

func _ready() -> void:
	if linked_signal != null and linked_signal.data != null and linked_signal.data.puzzle != null:
		linked_signal.data.puzzle.ensure_puzzle_generated()
		puzzle_config = linked_signal.data.puzzle.get_fuzz_config()
	if puzzle_config == null:
		puzzle_config = FuzzPuzzleConfig.new()
	$Layout/Title.gui_input.connect(_title_input)
	reset_puzzle(puzzle_config)

func reset_puzzle(settings: FuzzPuzzleConfig, fixed_angle_deg: float = -1.0) -> void:
	puzzle_config = settings
	state.reset(settings, fixed_angle_deg)
	impacts.clear()
	_solved_emitted = false
	aim_angle = -PI * 0.5
	_refresh()

func has_puzzle_focus() -> bool:
	var owner := get_viewport().gui_get_focus_owner()
	return is_visible_in_tree() and (owner == self or (owner != null and is_ancestor_of(owner)))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
	if event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset
	# Clicking a non-focusable part of the game must also relinquish focus.
	if event is InputEventMouseButton and event.pressed and not get_global_rect().has_point(get_global_mouse_position()) and has_puzzle_focus():
		var owner := get_viewport().gui_get_focus_owner()
		owner.release_focus()

func arena_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not has_puzzle_focus():
			grab_focus() # Activation click does not spend ammo.
		else:
			_aim_at(event.position)
			fire_packet()
		arena.accept_event()
	elif event is InputEventMouseMotion and has_puzzle_focus():
		_aim_at(event.position)

func _aim_at(point: Vector2) -> void:
	if not has_puzzle_focus() or state.solved:
		return
	var direction := point - arena.size * 0.5
	if direction.length_squared() > 1.0:
		aim_angle = direction.angle()
	arena.queue_redraw()

func fire_packet() -> bool:
	if not has_puzzle_focus():
		return false
	var fired := state.fire(aim_angle)
	_refresh()
	return fired

func _process(delta: float) -> void:
	for impact in impacts:
		impact["age"] += delta
	impacts = impacts.filter(func(hit: Dictionary) -> bool: return hit["age"] < state.config.impact_hold_sec + state.config.impact_fade_sec)
	impacts.append_array(state.advance(delta))
	_refresh()
	if state.solved and not _solved_emitted:
		_solved_emitted = true
		puzzle_solved.emit()

func _refresh() -> void:
	if not is_node_ready():
		return
	progress_bar.max_value = state.config.target_points
	progress_bar.value = state.progress
	readout.text = "POINTS %.1f / %.1f    PACKETS %d / %d" % [state.progress, state.config.target_points, state.ammo, state.config.max_ammo]
	focus_label.text = "ACCESS ESTABLISHED" if state.solved else ("FOCUSED // Move to aim. Left-click to fire." if has_puzzle_focus() else "Click to focus // Packets continue in the background.")
	arena.queue_redraw()

func _title_input(event: InputEvent) -> void:
	# Floating windows drag by their title. Docked hardware owns positioning.
	if not get_parent() is CanvasLayer:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			grab_focus()
			_drag_offset = get_global_mouse_position() - global_position
