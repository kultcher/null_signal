# grid_layer.gd
# Handles drawing and animating grid

extends Node2D

@onready var timeline_manager = $"../TimelineManager"
@onready var runner_team = $RunnerTeam
@onready var debug_label = $Debug

# CONFIGURATION
var LANE_GRID_COLOR = Color(0.169, 0.733, 0.588, 0.75)
var CELL_GRID_COLOR = Color(0.275, 0.699, 0.771, 0.2)

@onready var cell_width: float = timeline_manager.cell_width_px
@onready var lane_height: float = timeline_manager.lane_height
@onready var screen_width: float = timeline_manager.screen_width
@onready var screen_height: float = timeline_manager.screen_height


var time_elapsed: float = 0.0
const RUNNER_EDGE_FADE_PX := 40.0

# Full-width backdrop/overlay rects that should cover the whole map area.
@onready var _backdrop_rects: Array[Control] = [
	$TimelineBaseRect,
	$TimelineBreathEffect,
	$TimelineDataStream,
	$NullSpikeSyncOverlay,
]
@onready var facility_map_layer = get_node_or_null("FacilityMapLayer")

func _ready():
	if runner_team:
		_update_runner_team_position()
	_apply_map_layout()
	timeline_manager.layout_changed.connect(func(_size: Vector2) -> void: _apply_map_layout())

func _apply_map_layout() -> void:
	if not timeline_manager.map_mode:
		return
	var map_height: float = timeline_manager.get_timeline_height()
	for rect in _backdrop_rects:
		if rect == null:
			continue
		rect.offset_right = timeline_manager.screen_width
		rect.offset_bottom = rect.offset_top + map_height + 10.0

func _has_facility_rooms() -> bool:
	return facility_map_layer != null and facility_map_layer.has_rooms()

func _process(delta):
	queue_redraw()
	if timeline_manager.null_spike_active:
		time_elapsed += delta * 2
	else:
		time_elapsed += delta
	_update_runner_team_position()
	var display_string = "Current cell pos:%.1f" % floor(timeline_manager.current_cell) + "Time elapsed: %.1f" % time_elapsed
	debug_label.text = display_string

func _update_runner_team_position() -> void:
	if runner_team == null:
		return
	var pos: Vector2 = timeline_manager.get_runner_screen_pos()
	runner_team.position = pos
	if timeline_manager.map_mode:
		# Fade the runner out as the route leaves the map (e.g. around a corner).
		var rect: Rect2 = timeline_manager.get_map_rect()
		var edge_dist := minf(minf(pos.y - rect.position.y, rect.end.y - pos.y), minf(pos.x - rect.position.x, rect.end.x - pos.x))
		runner_team.modulate.a = clampf(edge_dist / RUNNER_EDGE_FADE_PX, 0.0, 1.0)
	else:
		runner_team.modulate.a = 1.0

func _draw():
	cell_width = timeline_manager.cell_width_px
	lane_height = timeline_manager.lane_height
	var lane_top: float = timeline_manager.lane_origin_y
	var lane_bottom: float = lane_top + (lane_height * timeline_manager.LANES)

	# Facility map draws its own floorplan; the lane grid is only a fallback
	# for runs without authored rooms.
	if _has_facility_rooms():
		return

	## --- DRAW HORIZONTAL LANES ---
	for i in range(timeline_manager.LANES + 1):
		var y_pos = lane_top + (i * lane_height)
		draw_line(
			Vector2(0, y_pos),
			Vector2(screen_width, y_pos),
			LANE_GRID_COLOR,
			1.0 
		)

	# 1. Where is the Runner?
	var runner_pos = timeline_manager.get_view_cell_pos()

	# 2. Where is the Left Edge of the screen in "World Coordinates"?
	# If runner is at 100, and offset is 1.5... Left edge is 98.5.
	var left_edge_world_pos = runner_pos - timeline_manager.runner_screen_offset_cells

	# 3. Find first visible grid line index based on Left Edge
	var first_visible_index = floor(left_edge_world_pos)

	# 4. Calculate offset from the Left Edge of the screen
	# e.g. Line 99 - Edge 98.5 = 0.5 cells from left
	var distance_from_edge_cells = first_visible_index - left_edge_world_pos

	# 5. Convert to pixels
	var draw_x = timeline_manager.cells_to_pixels(distance_from_edge_cells)


	while draw_x < screen_width + cell_width:
		if draw_x > -10: 
			draw_line(
				Vector2(draw_x, lane_top),
				Vector2(draw_x, lane_bottom),
				CELL_GRID_COLOR, 
				2.0) 
		draw_x += cell_width
