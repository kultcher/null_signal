# facility_map_layer.gd
# Draws the top-down facility map (rooms, walls, props, runner route) in
# map mode. Uses TimelineManager's spatial conversions, so it moves with the
# view exactly like signals do. Only the active feed section is drawn, and all
# drawing is clipped to the map area so side rooms can trail off-screen.

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
const FEED_LABEL_COLOR := Color(0.0, 0.85, 1.0, 0.55)
const MODEL_EDGE_COLOR := Color(0.35, 0.9, 0.8, 0.35)
const MODEL_TOP_COLOR := Color(0.45, 1.0, 0.9, 0.7)
const MODEL_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const MODEL_DISABLED_MULT := Color(0.6, 0.6, 0.6, 0.45)
const MODEL_CIRCLE_SEGMENTS := 16
const PATH_AHEAD_COLOR := Color(0.0, 0.85, 1.0, 0.4)
const PATH_BEHIND_COLOR := Color(0.0, 0.85, 1.0, 0.1)

const WALL_WIDTH := 3.0
const WALL_GLOW_WIDTH := 10.0
# Doorway half-size (in lanes) where the runner's route crosses a wall.
const DOORWAY_HALF_LANES := 0.4
const TILE_CELLS := 0.5
const PATH_DASH_PX := 14.0
const PATH_GAP_PX := 10.0
const PATH_WIDTH := 2.5

@export var timeline_manager_path: NodePath = ^"../../TimelineManager"
@onready var timeline_manager = get_node(timeline_manager_path)

# The debug viewer supplies an isolated projection and authored signals.
# Defaults preserve the live feed renderer's behavior.
var preview_mode := false
var preview_sections: Array[FacilitySection] = []
var preview_signals: Array[Dictionary] = []
var draw_route := true
var model_scale := 1.0

var _font: Font = preload("res://Visuals/Fonts/ShareTechMono-Regular.ttf")
var _clip := Rect2()

func _process(_delta: float) -> void:
	if preview_mode:
		return # The viewer redraws only when its data or view changes.
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

	_clip = timeline_manager.get_map_rect()
	var sections: Array[FacilitySection] = []
	if preview_mode:
		sections.assign(preview_sections)
	else:
		sections.append(timeline_manager.get_current_section())
	var left_cell: float = timeline_manager.screen_x_to_cell(-64.0)
	var right_cell: float = timeline_manager.screen_x_to_cell(timeline_manager.screen_width + 64.0)
	var rooms: Array[FacilityRoom] = []
	for section in sections:
		for room in timeline_manager.facility_layout.get_rooms_in_section(section):
			if room.end_cell >= left_cell and room.start_cell <= right_cell:
				rooms.append(room)

	for room in rooms:
		_draw_floor(room, left_cell, right_cell)
	for room in rooms:
		_draw_props(room)
	_draw_signal_models()
	if draw_route:
		for section in sections:
			_draw_runner_path(section)
	for room in rooms:
		if not room.is_exterior():
			var section: FacilitySection = timeline_manager.facility_layout.get_section_for_cell((room.start_cell + room.end_cell) * 0.5)
			for candidate in sections:
				if candidate.id == room.section_id:
					section = candidate
					break
			_draw_walls(room, section)
	for room in rooms:
		_draw_label(room)
	if not preview_mode:
		_draw_feed_label(sections[0])

# --- helpers ---

func _to_screen(cell: float, lane_edge: float) -> Vector2:
	return timeline_manager.cell_lane_to_screen(cell, lane_edge)

func _room_screen_rect(room: FacilityRoom) -> Rect2:
	var top_left := _to_screen(room.start_cell, room.lane_top)
	var bottom_right := _to_screen(room.end_cell, room.lane_bottom)
	return Rect2(top_left, bottom_right - top_left)

func _lane_to_cells(lanes: float) -> float:
	return lanes * timeline_manager.lane_height / maxf(1.0, timeline_manager.cell_width_px)

# --- clipped primitives ---

func _rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0) -> void:
	if filled:
		var clipped := rect.intersection(_clip)
		if clipped.has_area():
			draw_rect(clipped, color, true)
		return
	# Outline: draw each edge as a clipped line.
	var a := rect.position
	var b := Vector2(rect.end.x, rect.position.y)
	var c := rect.end
	var d := Vector2(rect.position.x, rect.end.y)
	for edge in [[a, b], [b, c], [c, d], [d, a]]:
		_line(edge[0], edge[1], color, width)

func _line(from: Vector2, to: Vector2, color: Color, width: float = 1.0) -> void:
	var seg := _clip_segment(from, to)
	if seg.is_empty():
		return
	draw_line(seg[0], seg[1], color, width)

func _text(pos: Vector2, text: String, max_width: float, size: int, color: Color) -> void:
	if not _clip.has_point(pos):
		return
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, max_width, size, color)

# Liang-Barsky clip of a segment against _clip. Returns [] if fully outside.
func _clip_segment(from: Vector2, to: Vector2) -> Array:
	var params := _clip_params(from, to)
	if params.is_empty():
		return []
	var d := to - from
	return [from + d * params[0], from + d * params[1]]

# Visible parameter range [t0, t1] of a segment inside _clip, or [] if none.
func _clip_params(from: Vector2, to: Vector2) -> Array:
	var d := to - from
	var t0 := 0.0
	var t1 := 1.0
	var checks := [
		[-d.x, from.x - _clip.position.x],
		[d.x, _clip.end.x - from.x],
		[-d.y, from.y - _clip.position.y],
		[d.y, _clip.end.y - from.y],
	]
	for check in checks:
		var p: float = check[0]
		var q: float = check[1]
		if is_zero_approx(p):
			if q < 0.0:
				return []
			continue
		var r := q / p
		if p < 0.0:
			if r > t1:
				return []
			t0 = maxf(t0, r)
		else:
			if r < t0:
				return []
			t1 = minf(t1, r)
	return [t0, t1]

# --- floors / props ---

func _draw_floor(room: FacilityRoom, left_cell: float, right_cell: float) -> void:
	var rect := _room_screen_rect(room)
	if room.is_exterior():
		_rect(rect, EXTERIOR_COLOR)
		var dot_step_lanes := 0.5
		var cell := ceilf(maxf(room.start_cell, left_cell) / TILE_CELLS) * TILE_CELLS
		while cell <= minf(room.end_cell, right_cell):
			var lane := ceilf(room.lane_top / dot_step_lanes) * dot_step_lanes
			while lane <= room.lane_bottom:
				var dot := _to_screen(cell, lane)
				if _clip.has_point(dot):
					draw_circle(dot, 1.5, EXTERIOR_DOT_COLOR)
				lane += dot_step_lanes
			cell += TILE_CELLS
		return

	_rect(rect, FLOOR_COLOR)

	# Floor tiles: vertical lines every half cell, horizontal lines every lane.
	var tile_cell := ceilf(maxf(room.start_cell, left_cell) / TILE_CELLS) * TILE_CELLS
	while tile_cell < minf(room.end_cell, right_cell):
		var x: float = timeline_manager.cell_to_screen_x(tile_cell)
		_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), FLOOR_TILE_COLOR, 1.0)
		tile_cell += TILE_CELLS
	var lane_line := ceilf(room.lane_top) - 0.5
	while lane_line < room.lane_bottom:
		if lane_line > room.lane_top:
			var y: float = timeline_manager.lane_to_y(lane_line)
			_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), FLOOR_TILE_COLOR, 1.0)
		lane_line += 1.0

func _draw_props(room: FacilityRoom) -> void:
	for prop in room.props:
		var prop_rect: Rect2 = prop["rect"]
		var top_left := _to_screen(prop_rect.position.x, prop_rect.position.y)
		var bottom_right := _to_screen(prop_rect.end.x, prop_rect.end.y)
		var screen_rect := Rect2(top_left, bottom_right - top_left)
		var model := WireframeModels.get_model(prop.get("model", &""))
		if model.is_empty():
			_rect(screen_rect, PROP_FILL_COLOR)
			_rect(screen_rect, PROP_EDGE_COLOR, false, 1.5)
		else:
			_draw_model(model, screen_rect, Color.WHITE, int(prop.get("rot", 0)))
		var prop_label: String = prop.get("label", "")
		if not prop_label.is_empty() and screen_rect.size.x > 40.0:
			_text(screen_rect.position + Vector2(6, 14), prop_label, screen_rect.size.x - 12.0, 11, PROP_LABEL_COLOR)

# --- wireframe models ---

# Hardware under signals (valves, fabricators, consoles...), sized by the model.
func _draw_signal_models() -> void:
	if preview_mode:
		for entry in preview_signals:
			var model := WireframeModels.get_model(WireframeModels.model_for_signal(entry["data"]))
			if model.is_empty():
				continue
			var size: Vector2 = model["size"] * model_scale
			var center := _to_screen(entry["cell"], entry["data"].lane)
			_draw_model(model, Rect2(center - size * 0.5, size))
		return
	var signal_manager = CommandDispatch.signal_manager
	if signal_manager == null or not signal_manager.visible:
		return
	for active_sig in signal_manager.signal_queue:
		if active_sig == null or active_sig.instance_node == null:
			continue
		var model := WireframeModels.get_model(WireframeModels.model_for_signal(active_sig.data))
		if model.is_empty():
			continue
		var size: Vector2 = model["size"]
		var center: Vector2 = active_sig.instance_node.position
		var tint := MODEL_DISABLED_MULT if active_sig.is_disabled else Color.WHITE
		_draw_model(model, Rect2(center - size * 0.5, size), tint)

# Draws a model's parts fitted to `rect` (its footprint on the floor).
# `rot` turns the model by quarter turns clockwise; `rect` is the footprint
# after rotation.
func _draw_model(model: Dictionary, rect: Rect2, tint: Color = Color.WHITE, rot: int = 0) -> void:
	_rect(rect, MODEL_SHADOW_COLOR * Color(1, 1, 1, tint.a))
	var edge := MODEL_EDGE_COLOR * tint
	var top := MODEL_TOP_COLOR * tint
	var unit := minf(rect.size.x, rect.size.y)
	for part in model["parts"]:
		match part["t"]:
			"box":
				var r: Rect2 = WireframeModels.rotate_rect(part["r"], rot)
				var z: Vector2 = part["z"]
				var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
				for i in 4:
					var a: Vector2 = corners[i]
					var b: Vector2 = corners[(i + 1) % 4]
					_line(_project(rect, a, z.x), _project(rect, b, z.x), edge, 1.0)
					_line(_project(rect, a, z.y), _project(rect, b, z.y), top, 1.4)
					_line(_project(rect, a, z.x), _project(rect, a, z.y), edge, 1.0)
			"cyl":
				var c: Vector2 = WireframeModels.rotate_point(part["c"], rot)
				var radius: float = part["rad"] * unit
				var z: Vector2 = part["z"]
				_draw_circle_at(rect, c, radius, z.x, edge, 1.0)
				_draw_circle_at(rect, c, radius, z.y, top, 1.4)
				# Silhouette edges, perpendicular to the height projection.
				var side := WireframeModels.HEIGHT_PROJECTION.normalized().orthogonal() * radius
				for side_sign in [-1.0, 1.0]:
					var base: Vector2 = _project(rect, c, z.x) + side * side_sign
					var tip: Vector2 = _project(rect, c, z.y) + side * side_sign
					_line(base, tip, edge, 1.0)
			"ring":
				_draw_circle_at(rect, WireframeModels.rotate_point(part["c"], rot), part["rad"] * unit, part["z"], top, 1.4)
			"line":
				var a3: Vector3 = part["a"]
				var b3: Vector3 = part["b"]
				var a2 := WireframeModels.rotate_point(Vector2(a3.x, a3.y), rot)
				var b2 := WireframeModels.rotate_point(Vector2(b3.x, b3.y), rot)
				_line(_project(rect, a2, a3.z), _project(rect, b2, b3.z), top, 1.2)

func _project(rect: Rect2, normalized: Vector2, z: float) -> Vector2:
	return rect.position + (normalized * rect.size) + (WireframeModels.HEIGHT_PROJECTION * z * model_scale)

func _draw_circle_at(rect: Rect2, normalized_center: Vector2, radius: float, z: float, color: Color, width: float) -> void:
	var center := _project(rect, normalized_center, 0.0) + (WireframeModels.HEIGHT_PROJECTION * z * model_scale)
	var prev := center + Vector2(radius, 0.0)
	for i in range(1, MODEL_CIRCLE_SEGMENTS + 1):
		var angle := TAU * float(i) / float(MODEL_CIRCLE_SEGMENTS)
		var next := center + Vector2(cos(angle), sin(angle)) * radius
		_line(prev, next, color, width)
		prev = next

# --- walls ---

func _draw_walls(room: FacilityRoom, section: FacilitySection) -> void:
	var points := section.path_points
	var doorway_half_cells := _lane_to_cells(DOORWAY_HALF_LANES)

	# Left/right walls: doorway wherever the route crosses them.
	for edge_cell in [room.start_cell, room.end_cell]:
		var cuts: Array = []
		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i + 1]
			if is_equal_approx(a.x, b.x) or edge_cell < minf(a.x, b.x) or edge_cell > maxf(a.x, b.x):
				continue
			var lane := lerpf(a.y, b.y, (edge_cell - a.x) / (b.x - a.x))
			cuts.append(Vector2(lane - DOORWAY_HALF_LANES, lane + DOORWAY_HALF_LANES))
		for span in _subtract_spans([Vector2(room.lane_top, room.lane_bottom)], cuts):
			_draw_wall_segment(_to_screen(edge_cell, span.x), _to_screen(edge_cell, span.y))

	# Top/bottom walls: authored openings plus route crossings.
	for side in ["top", "bottom"]:
		var lane_edge := room.lane_top if side == "top" else room.lane_bottom
		var cuts: Array = []
		for opening in room.wall_openings:
			if opening.get("side", "") == side:
				cuts.append(Vector2(float(opening["from_cell"]), float(opening["to_cell"])))
		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i + 1]
			if is_equal_approx(a.y, b.y) or lane_edge < minf(a.y, b.y) or lane_edge > maxf(a.y, b.y):
				continue
			var cell := lerpf(a.x, b.x, (lane_edge - a.y) / (b.y - a.y))
			cuts.append(Vector2(cell - doorway_half_cells, cell + doorway_half_cells))
		for span in _subtract_spans([Vector2(room.start_cell, room.end_cell)], cuts):
			_draw_wall_segment(_to_screen(span.x, lane_edge), _to_screen(span.y, lane_edge))

func _draw_wall_segment(from: Vector2, to: Vector2) -> void:
	if from.distance_squared_to(to) < 1.0:
		return
	_line(from, to, WALL_GLOW_COLOR, WALL_GLOW_WIDTH)
	_line(from, to, WALL_COLOR, WALL_WIDTH)

# --- labels ---

func _draw_label(room: FacilityRoom) -> void:
	if room.label.is_empty():
		return
	var rect := _room_screen_rect(room).intersection(_clip)
	if not rect.has_area():
		return
	# Pin the label to the visible part of the room so it stays readable
	# while the room scrolls past.
	var available := rect.size.x - 20.0
	if available < 60.0 or rect.size.y < 30.0:
		return
	_text(rect.position + Vector2(10.0, 20.0), room.label, available, 14, LABEL_COLOR)

func _draw_feed_label(section: FacilitySection) -> void:
	var sections: Array[FacilitySection] = timeline_manager.facility_layout.sections
	if sections.size() <= 1:
		return
	# Relay mesh zone currently mapped (see feed_switch_overlay.gd).
	var text := "MESH %02d // %s" % [sections.find(section) + 1, section.label]
	var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var pos := Vector2(_clip.end.x - text_size.x - 16.0, _clip.position.y + 22.0)
	draw_rect(Rect2(pos + Vector2(-8.0, -16.0), text_size + Vector2(16.0, 8.0)), Color(0.0, 0.0, 0.0, 0.75), true)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, FEED_LABEL_COLOR)

# --- runner route ---

func _draw_runner_path(section: FacilitySection) -> void:
	var points := section.path_points
	if points.size() < 2:
		return
	var screen_points := PackedVector2Array()
	for point in points:
		screen_points.append(_to_screen(point.x, point.y))

	# Split the route at the runner: dim behind, bright ahead.
	var runner_local: float = -1.0 if preview_mode else timeline_manager.path_progress - section.progress_start
	var behind := PackedVector2Array([screen_points[0]])
	var ahead := PackedVector2Array()
	var walked := 0.0
	var layout: FacilityLayout = timeline_manager.facility_layout
	for i in range(points.size() - 1):
		var seg_len := layout.segment_length(points[i], points[i + 1])
		if ahead.is_empty() and walked + seg_len >= runner_local:
			var t := 0.0 if seg_len <= 0.0 else clampf((runner_local - walked) / seg_len, 0.0, 1.0)
			var split := screen_points[i].lerp(screen_points[i + 1], t)
			behind.append(split)
			ahead.append(split)
		if ahead.is_empty():
			behind.append(screen_points[i + 1])
		else:
			ahead.append(screen_points[i + 1])
		walked += seg_len

	var behind_len := _draw_dashed_polyline(behind, PATH_BEHIND_COLOR, 0.0)
	_draw_dashed_polyline(ahead, PATH_AHEAD_COLOR, behind_len)

	# Corner markers: small chevron where the route changes direction ahead.
	for i in range(1, ahead.size() - 1):
		var into := (ahead[i] - ahead[i - 1]).normalized()
		var out := (ahead[i + 1] - ahead[i]).normalized()
		if into.dot(out) > 0.95:
			continue
		var tip := ahead[i] + out * 18.0
		var side := out.orthogonal() * 7.0
		_line(tip - out * 9.0 + side, tip, PATH_AHEAD_COLOR, PATH_WIDTH)
		_line(tip - out * 9.0 - side, tip, PATH_AHEAD_COLOR, PATH_WIDTH)

# Draws dashes along a polyline. `phase` is the distance already covered
# before this polyline starts, so dashes stay anchored to the route.
# Returns the polyline's length plus `phase`.
func _draw_dashed_polyline(points: PackedVector2Array, color: Color, phase: float) -> float:
	var period := PATH_DASH_PX + PATH_GAP_PX
	var distance := phase
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var seg_len := a.distance_to(b)
		if seg_len <= 0.0:
			continue
		var visible := _clip_params(a, b)
		if not visible.is_empty():
			var dir := (b - a) / seg_len
			var vis_from: float = visible[0] * seg_len
			var vis_to: float = visible[1] * seg_len
			# First dash start at or before the visible part, on the route's dash grid.
			var local := vis_from - fposmod(distance + vis_from, period)
			while local < vis_to:
				var d0 := maxf(local, vis_from)
				var d1 := minf(local + PATH_DASH_PX, vis_to)
				if d1 > d0:
					draw_line(a + dir * d0, a + dir * d1, color, PATH_WIDTH)
				local += period
		distance += seg_len
	return distance

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
