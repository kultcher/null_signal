# facility_map_layer.gd
# Draws the top-down facility map (rooms, walls, props, runner path) in
# map mode. Uses TimelineManager's spatial conversions, so it scrolls with
# the runner exactly like signals do.

extends Node2D

const FLOOR_COLOR := Color(0.035, 0.07, 0.085, 0.92)
const FLOOR_TILE_COLOR := Color(0.275, 0.699, 0.771, 0.07)
const EXTERIOR_COLOR := Color(0.02, 0.035, 0.04, 0.85)
const EXTERIOR_DOT_COLOR := Color(0.275, 0.699, 0.771, 0.12)
const WALL_COLOR := Color(0.169, 0.733, 0.588, 0.85)
const WALL_GLOW_COLOR := Color(0.169, 0.733, 0.588, 0.12)
const PROP_FILL_COLOR := Color(0.169, 0.733, 0.588, 0.06)
const PROP_EDGE_COLOR := Color(0.169, 0.733, 0.588, 0.35)
const LABEL_COLOR := Color(0.169, 0.733, 0.588, 0.6)
const PROP_LABEL_COLOR := Color(0.169, 0.733, 0.588, 0.35)
const PATH_AHEAD_COLOR := Color(0.0, 0.85, 1.0, 0.35)
const PATH_BEHIND_COLOR := Color(0.0, 0.85, 1.0, 0.1)

const WALL_WIDTH := 3.0
const WALL_GLOW_WIDTH := 10.0
# Doorway half-height in lanes where the runner's path crosses a wall.
const DOORWAY_HALF_LANES := 0.4
const TILE_CELLS := 0.5
const PATH_DASH_PX := 14.0
const PATH_GAP_PX := 10.0

@onready var timeline_manager = $"../../TimelineManager"

var _font: Font = preload("res://Visuals/Fonts/ShareTechMono-Regular.ttf")

func _process(_delta: float) -> void:
	visible = timeline_manager != null and timeline_manager.map_mode
	if visible:
		queue_redraw()

func has_rooms() -> bool:
	return timeline_manager != null \
		and timeline_manager.facility_layout != null \
		and timeline_manager.facility_layout.has_rooms()

func _draw() -> void:
	if not has_rooms():
		return

	var left_cell: float = timeline_manager.screen_x_to_cell(-64.0)
	var right_cell: float = timeline_manager.screen_x_to_cell(timeline_manager.screen_width + 64.0)
	var rooms: Array[FacilityRoom] = timeline_manager.facility_layout.get_rooms_in_range(left_cell, right_cell)

	for room in rooms:
		_draw_floor(room, left_cell, right_cell)
	for room in rooms:
		_draw_props(room)
	_draw_runner_path()
	for room in rooms:
		if not room.is_exterior():
			_draw_walls(room)
	for room in rooms:
		_draw_label(room)

# --- helpers ---

func _to_screen(cell: float, lane_edge: float) -> Vector2:
	return timeline_manager.cell_lane_to_screen(cell, lane_edge)

func _room_screen_rect(room: FacilityRoom) -> Rect2:
	var top_left := _to_screen(room.start_cell, room.lane_top)
	var bottom_right := _to_screen(room.end_cell, room.lane_bottom)
	return Rect2(top_left, bottom_right - top_left)

func _draw_floor(room: FacilityRoom, left_cell: float, right_cell: float) -> void:
	var rect := _room_screen_rect(room)
	if room.is_exterior():
		draw_rect(rect, EXTERIOR_COLOR, true)
		var dot_step_lanes := 0.5
		var cell := ceilf(maxf(room.start_cell, left_cell) / TILE_CELLS) * TILE_CELLS
		while cell <= minf(room.end_cell, right_cell):
			var lane := ceilf(room.lane_top / dot_step_lanes) * dot_step_lanes
			while lane <= room.lane_bottom:
				draw_circle(_to_screen(cell, lane), 1.5, EXTERIOR_DOT_COLOR)
				lane += dot_step_lanes
			cell += TILE_CELLS
		return

	draw_rect(rect, FLOOR_COLOR, true)

	# Floor tiles: vertical lines every half cell, horizontal lines every lane.
	var tile_cell := ceilf(maxf(room.start_cell, left_cell) / TILE_CELLS) * TILE_CELLS
	while tile_cell < minf(room.end_cell, right_cell):
		var x: float = timeline_manager.cell_to_screen_x(tile_cell)
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), FLOOR_TILE_COLOR, 1.0)
		tile_cell += TILE_CELLS
	var lane_line := ceilf(room.lane_top) - 0.5
	while lane_line < room.lane_bottom:
		if lane_line > room.lane_top:
			var y: float = timeline_manager.lane_to_y(lane_line)
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), FLOOR_TILE_COLOR, 1.0)
		lane_line += 1.0

func _draw_props(room: FacilityRoom) -> void:
	for prop in room.props:
		var prop_rect: Rect2 = prop["rect"]
		var top_left := _to_screen(prop_rect.position.x, prop_rect.position.y)
		var bottom_right := _to_screen(prop_rect.end.x, prop_rect.end.y)
		var screen_rect := Rect2(top_left, bottom_right - top_left)
		draw_rect(screen_rect, PROP_FILL_COLOR, true)
		draw_rect(screen_rect, PROP_EDGE_COLOR, false, 1.5)
		var prop_label: String = prop.get("label", "")
		if not prop_label.is_empty() and screen_rect.size.x > 40.0:
			draw_string(
				_font,
				screen_rect.position + Vector2(6, 14),
				prop_label,
				HORIZONTAL_ALIGNMENT_LEFT,
				screen_rect.size.x - 12.0,
				11,
				PROP_LABEL_COLOR
			)

func _draw_walls(room: FacilityRoom) -> void:
	var path_lane: float = timeline_manager.path_lane

	# Left/right walls: always leave a doorway where the runner's path crosses.
	for edge_cell in [room.start_cell, room.end_cell]:
		var spans := _subtract_spans(
			[Vector2(room.lane_top, room.lane_bottom)],
			[Vector2(path_lane - DOORWAY_HALF_LANES, path_lane + DOORWAY_HALF_LANES)]
		)
		for span in spans:
			_draw_wall_segment(_to_screen(edge_cell, span.x), _to_screen(edge_cell, span.y))

	# Top/bottom walls, minus authored openings.
	for side in ["top", "bottom"]:
		var lane_edge := room.lane_top if side == "top" else room.lane_bottom
		var cuts: Array = []
		for opening in room.wall_openings:
			if opening.get("side", "") == side:
				cuts.append(Vector2(float(opening["from_cell"]), float(opening["to_cell"])))
		for span in _subtract_spans([Vector2(room.start_cell, room.end_cell)], cuts):
			_draw_wall_segment(_to_screen(span.x, lane_edge), _to_screen(span.y, lane_edge))

func _draw_wall_segment(from: Vector2, to: Vector2) -> void:
	if from.distance_squared_to(to) < 1.0:
		return
	draw_line(from, to, WALL_GLOW_COLOR, WALL_GLOW_WIDTH)
	draw_line(from, to, WALL_COLOR, WALL_WIDTH)

func _draw_label(room: FacilityRoom) -> void:
	if room.label.is_empty():
		return
	var rect := _room_screen_rect(room)
	# Pin the label to the visible part of the room so it stays readable
	# while the room scrolls past.
	var label_x := maxf(rect.position.x, 0.0) + 10.0
	var available := rect.end.x - label_x - 10.0
	if available < 60.0:
		return
	draw_string(
		_font,
		Vector2(label_x, rect.position.y + 20.0),
		room.label,
		HORIZONTAL_ALIGNMENT_LEFT,
		available,
		14,
		LABEL_COLOR
	)

func _draw_runner_path() -> void:
	var y: float = timeline_manager.lane_to_y(timeline_manager.path_lane)
	var runner_x: float = timeline_manager.get_runner_screen_pos().x
	var last_room: FacilityRoom = timeline_manager.facility_layout.rooms.back()
	var end_x: float = minf(timeline_manager.cell_to_screen_x(last_room.end_cell), timeline_manager.screen_width)
	var first_room: FacilityRoom = timeline_manager.facility_layout.rooms.front()
	var start_x: float = maxf(timeline_manager.cell_to_screen_x(first_room.start_cell), 0.0)
	_draw_dashed(Vector2(start_x, y), Vector2(minf(runner_x, end_x), y), PATH_BEHIND_COLOR)
	_draw_dashed(Vector2(maxf(runner_x, start_x), y), Vector2(end_x, y), PATH_AHEAD_COLOR)

func _draw_dashed(from: Vector2, to: Vector2, color: Color) -> void:
	if to.x <= from.x:
		return
	# Anchor dashes to world space so they scroll with the floor.
	var period := PATH_DASH_PX + PATH_GAP_PX
	var world_offset: float = fposmod(timeline_manager.get_view_cell_pos() * timeline_manager.cell_width_px, period)
	var x := from.x - fposmod(from.x + world_offset, period)
	while x < to.x:
		var a := maxf(x, from.x)
		var b := minf(x + PATH_DASH_PX, to.x)
		if b > a:
			draw_line(Vector2(a, from.y), Vector2(b, from.y), color, 2.0)
		x += period

# Returns `spans` (Vector2(start, end) ranges) with every range in `cuts` removed.
func _subtract_spans(spans: Array, cuts: Array) -> Array:
	var result: Array = spans.duplicate()
	for cut in cuts:
		var next: Array = []
		for span in result:
			if cut.y <= span.x or cut.x >= span.y:
				next.append(span)
				continue
			if cut.x > span.x:
				next.append(Vector2(span.x, cut.x))
			if cut.y < span.y:
				next.append(Vector2(cut.y, span.y))
		result = next
	return result
