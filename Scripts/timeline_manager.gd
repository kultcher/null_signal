# timeline_manager.gd
# Primary "source of truth," tracks distance from Runners to each Signal

extends Node2D

# SETTINGS
@export var BASE_CELLS_PER_SECOND: float = 0.15		# 0.2 ~= 30 seconds window from spawn to contact
@export var slow_speed_modifier: float = 0.5
@export var fast_speed_modifier: float = 3
@export var null_spike_time_scale: float = 0.5
@export var null_spike_transition_duration: float = 0.50
@export var runner_screen_offset_cells: float = 1
@export var timeline_height_ratio: float = 0.25
@export var min_timeline_height_px: float = 180.0
@export var max_timeline_height_px: float = 360.0

@export var signal_interaction_range_cells: float = 8.0

# MAP MODE
# When enabled, the timeline strip is replaced by a top-down facility map.
# The runner follows the run's authored route (FacilityLayout); speed is
# measured in cells of path length. current_cell_pos stays the runner's x on
# the map, so everything keyed on cells (triggers, ranges) keeps working.
# The map is split into feed sections: the view follows the runner, holds once
# the section's end is on screen, and cuts to the next section.
@export var map_mode: bool = true
@export var map_height_px: float = 560.0
@export var map_lane_spacing_px: float = 90.0
@export var path_lane: float = 2.0

@export var signal_sweep_enabled: bool = true
@export var signal_sweep_cycle_sec: float = 8.5
@export var signal_sweep_start_x: float = -0.1
@export var signal_sweep_end_x: float = 1.1


# TIMELINE DIMENSIONS
var LANES = 5
var VISIBLE_CELLS = 8.0
var screen_width: float
var screen_height: float
var cell_width_px: float
var lane_height: float
var lane_origin_y: float = 0.0

# STATE
var cells_per_second: float = BASE_CELLS_PER_SECOND
var current_cell_pos: float = 0.0
var last_emitted_cell: int = -1
var current_cell: int
var current_speed_mult: float = 1.0
var null_spike_active: bool = false
var tutorial_locked: bool = false
var _time_scale_tween: Tween
var _view_offset_tween: Tween
var view_offset_cells: float = 0.0
var signal_sweep_normalized_x: float = 1.1
var facility_layout: FacilityLayout = FacilityLayout.new():
	set = _set_facility_layout

# Route state. path_progress is distance travelled along the route (cells);
# runner_lane_pos is the runner's current lane on the map.
var path_progress: float = 0.0
var runner_lane_pos: float = 2.0
var current_section_index: int = 0
var _straight_route := FacilityLayout.new()

# REGISTRATION
@onready var signal_manager = $"../SignalManager"
@onready var breathe_overlay = $"../GridLayer/TimelineBreathEffect"
@onready var _sweep_breathe_material: Material = breathe_overlay.material

# SIGNALS (to update UI later)
signal speed_changed(new_speed)
signal layout_changed(viewport_size: Vector2)
signal section_changed(section: FacilitySection)

func _ready():
	CommandDispatch.timeline_manager = self
	Engine.time_scale = 1.0
	get_viewport().size_changed.connect(_refresh_layout_metrics)
	_refresh_layout_metrics()
	signal_sweep_normalized_x = signal_sweep_start_x
	set_runner_cell(current_cell_pos)

	GlobalEvents.runners_stopped.connect(_on_runners_stopped)
	GlobalEvents.runners_resumed.connect(_on_runners_resumed)
	GlobalEvents.activate_null_spike.connect(activate_null_spike)
	GlobalEvents.deactivate_null_spike.connect(deactivate_null_spike)
	GlobalEvents.tutorial_lock_changed.connect(_on_tutorial_lock_changed)

func _process(delta):
	_handle_input()
	_update_signal_sweep(delta)
	
	var actual_speed = cells_per_second * current_speed_mult
	path_progress += actual_speed * delta
	_apply_path_progress()

	current_cell = floor(current_cell_pos) as int
	if current_cell != last_emitted_cell:
		last_emitted_cell = current_cell
		GlobalEvents.cell_reached.emit(current_cell)

func cells_to_pixels(cells: float) -> float:
	return cells * cell_width_px

# Cell shown at the runner's usual screen offset. In map mode this follows the
# runner but stays inside the active section, so the view holds once the
# section's end reaches the right edge of the screen.
func get_view_cell_pos() -> float:
	var view_cell := current_cell_pos
	if map_mode:
		var section := get_current_section()
		var view_min := section.start_cell
		var view_max := maxf(view_min, section.end_cell - (VISIBLE_CELLS - runner_screen_offset_cells))
		view_cell = clampf(view_cell, view_min, view_max)
	return view_cell + view_offset_cells

func set_view_offset_cells(target_offset_cells: float, duration: float = 0.0) -> void:
	if _view_offset_tween != null and _view_offset_tween.is_valid():
		_view_offset_tween.kill()

	if duration <= 0.0:
		view_offset_cells = target_offset_cells
		return

	_view_offset_tween = create_tween()
	_view_offset_tween.set_trans(Tween.TRANS_SINE)
	_view_offset_tween.set_ease(Tween.EASE_IN)
	_view_offset_tween.tween_property(self, "view_offset_cells", target_offset_cells, duration)

func clear_view_offset(duration: float = 0.0) -> void:
	set_view_offset_cells(0.0, duration)

func get_timeline_height() -> float:
	if map_mode:
		return map_height_px
	return lane_height * LANES

# --- SPATIAL CONVERSIONS ---
# Everything that places things on screen should go through these, so the
# underlying layout (lanes today, a real path later) can change in one place.

func lane_to_y(lane_pos: float) -> float:
	return lane_origin_y + (lane_pos * lane_height) + (lane_height * 0.5)

func cell_to_screen_x(cell: float) -> float:
	var runner_screen_x := cells_to_pixels(runner_screen_offset_cells)
	return runner_screen_x + ((cell - get_view_cell_pos()) * cell_width_px)

func cell_lane_to_screen(cell: float, lane_pos: float) -> Vector2:
	return Vector2(cell_to_screen_x(cell), lane_to_y(lane_pos))

func screen_x_to_cell(screen_x: float) -> float:
	var runner_screen_x := cells_to_pixels(runner_screen_offset_cells)
	return get_view_cell_pos() + ((screen_x - runner_screen_x) / maxf(1.0, cell_width_px))

func get_runner_screen_pos() -> Vector2:
	return Vector2(cell_to_screen_x(current_cell_pos), lane_to_y(runner_lane_pos))

# Area of the timeline/map, in SignalTimeline-local coordinates.
func get_map_rect() -> Rect2:
	return Rect2(0.0, 0.0, screen_width, get_timeline_height())

# --- ROUTE / SECTIONS ---

func get_route() -> FacilityLayout:
	return facility_layout if map_mode else _straight_route

func get_current_section() -> FacilitySection:
	var sections := get_route().sections
	return sections[clampi(current_section_index, 0, sections.size() - 1)]

# Whether something spawned at `cell` belongs to the feed currently shown.
func is_cell_in_current_section(cell: float) -> bool:
	if not map_mode:
		return true
	return get_current_section().contains_cell(cell)

# Place the runner at the first point on the route that reaches `cell`.
func set_runner_cell(cell: float) -> void:
	path_progress = get_route().progress_at_cell(cell)
	_apply_path_progress(false)
	current_cell = floor(current_cell_pos) as int
	last_emitted_cell = current_cell

func _apply_path_progress(emit_section_change: bool = true) -> void:
	var route := get_route()
	var pos := route.sample_position(path_progress)
	current_cell_pos = pos.x
	runner_lane_pos = pos.y
	var section_index := route.get_section_index_for_progress(path_progress)
	if section_index != current_section_index:
		current_section_index = section_index
		if emit_section_change:
			section_changed.emit(get_current_section())

func _set_facility_layout(layout: FacilityLayout) -> void:
	facility_layout = layout if layout != null else FacilityLayout.new()
	_sync_route_scale()

func _sync_route_scale() -> void:
	if cell_width_px <= 0.0:
		return
	var scale := lane_height / cell_width_px
	facility_layout.set_lane_to_cell_scale(scale)
	_straight_route.set_lane_to_cell_scale(scale)

func get_viewport_size() -> Vector2:
	return Vector2(screen_width, screen_height)

func get_signal_sweep_x() -> float:
	return signal_sweep_normalized_x

func _refresh_layout_metrics() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	screen_width = viewport_size.x
	screen_height = viewport_size.y

	cell_width_px = screen_width / VISIBLE_CELLS
	if map_mode:
		lane_height = map_lane_spacing_px
		lane_origin_y = (map_height_px - (lane_height * LANES)) * 0.5
	else:
		var timeline_height := clampf(screen_height * timeline_height_ratio, min_timeline_height_px, max_timeline_height_px)
		lane_height = timeline_height / LANES
		lane_origin_y = 0.0
	_sync_route_scale()
	layout_changed.emit(viewport_size)

func _update_signal_sweep(delta: float) -> void:
	if not signal_sweep_enabled:
		signal_sweep_normalized_x = signal_sweep_start_x
		return

	if signal_sweep_cycle_sec <= 0.001:
		signal_sweep_normalized_x = signal_sweep_end_x
		return

	var distance := signal_sweep_end_x - signal_sweep_start_x
	var sweep_speed := distance / signal_sweep_cycle_sec
	signal_sweep_normalized_x += sweep_speed * delta

	if signal_sweep_normalized_x >= signal_sweep_end_x:
		signal_sweep_normalized_x = signal_sweep_start_x

	_sweep_breathe_material.set_shader_parameter(
		"sweep_position",
		get_signal_sweep_x()
	)


func _handle_input():
	if Input.is_action_just_pressed("null_spike"):
		toggle_null_spike()


	# runner speed handling
	current_speed_mult = 1.0
	if Input.is_action_pressed("ui_left"): 
		GlobalEvents.runner_slowdown.emit()
		current_speed_mult = slow_speed_modifier
	elif Input.is_action_pressed("ui_right"):
		GlobalEvents.runner_hustle.emit()
		current_speed_mult = fast_speed_modifier
		
	# Optional: Emit signal if you want UI to show "FAST FORWARD" text
	# emit_signal("speed_changed", current_speed_mult)

func toggle_null_spike():
	if not GlobalEvents.is_tutorial_feature_enabled("null_spike"):
		return
	if GlobalEvents.first_null_spike == true:
		#WARNING: Temporary fix for tutorial cutscene issues. Make sure it gets reenabled
		$"../GridLayer/TimelineBreathEffect".hide()
		GlobalEvents.activate_first_null_spike.emit()
		return

	if null_spike_active:
		GlobalEvents.deactivate_null_spike.emit()
	else:
		GlobalEvents.activate_null_spike.emit()

func deactivate_null_spike():
	null_spike_active = false
	#NOTE: Temporary
	_tween_time_scale(1.0)
	await get_tree().create_timer(.5).timeout
	$"../GridLayer/TimelineBreathEffect".show()

func activate_null_spike():
	null_spike_active = true
	_tween_time_scale(null_spike_time_scale)
	$"../GridLayer/TimelineBreathEffect".hide()



func _tween_time_scale(target_scale: float) -> void:
	if _time_scale_tween != null and _time_scale_tween.is_valid():
		_time_scale_tween.kill()

	_time_scale_tween = create_tween()
	_time_scale_tween.set_trans(Tween.TRANS_SINE)
	_time_scale_tween.set_ease(Tween.EASE_IN_OUT)
	_time_scale_tween.tween_property(Engine, "time_scale", target_scale, null_spike_transition_duration)

func _on_tutorial_lock_changed(locked: bool):
	tutorial_locked = locked

func _on_runners_stopped():
	cells_per_second = 0

func _on_runners_resumed():
	cells_per_second = BASE_CELLS_PER_SECOND
