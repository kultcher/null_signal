# Authoring overlays; uses the actual detection polygon and resolved patrol
# points from RunDefinition.build_runtime_signal(). No gameplay entities.
extends Node2D

@onready var viewer = $"../../.."
var _font: Font = preload("res://Visuals/Fonts/ShareTechMono-Regular.ttf")
const GRID := Color(0.35, 0.75, 0.82, 0.14)
const INK := Color(0.65, 0.9, 0.95)
const GOLD := Color(1.0, 0.8, 0.25)
const THREAT_CERTAIN := Color(1.0, 0.22, 0.2)
const THREAT_POSSIBLE := Color(1.0, 0.62, 0.15)
const THREAT_NEVER := Color(0.45, 0.6, 0.65)

func _draw() -> void:
	if viewer.facility_layout == null:
		return
	if viewer.distance_toggle.button_pressed:
		_draw_distances()
	if viewer.boundary_toggle.button_pressed:
		_draw_sections()
	if viewer.threat_toggle != null and viewer.threat_toggle.button_pressed:
		for entry in viewer.visible_entries():
			_draw_threat_bands(entry)
	for entry in viewer.visible_entries():
		_draw_signal(entry)
	if viewer.route_toggle.button_pressed and viewer.distance_toggle.button_pressed:
		_draw_route_distances()
	if not viewer.measurement.is_empty():
		_draw_ruler()
	if not viewer.start_location.is_empty():
		_draw_start_point()

func _label(point: Vector2, text: String, color: Color = INK, size: int = 13) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	draw_rect(Rect2(point + Vector2(-2.0, -size), Vector2(width + 4.0, size + 3.0)), Color(0.012, 0.025, 0.035, 0.85))
	draw_string(_font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)

# Adaptive 1/2/5 ticks keep the distance overlay readable at whole-level zoom.
func _tick_step(pixels_per_unit: float, target_px: float) -> float:
	var raw := target_px / pixels_per_unit
	var power := pow(10.0, floor(log(raw) / log(10.0)))
	for multiplier in [1.0, 2.0, 5.0, 10.0]:
		if power * multiplier >= raw:
			return power * multiplier
	return power * 10.0

func _draw_distances() -> void:
	var rect: Rect2 = viewer.get_map_rect()
	var from: Vector2 = viewer.screen_to_map(rect.position)
	var to: Vector2 = viewer.screen_to_map(rect.end)
	var cell_step := _tick_step(viewer.cell_width_px, 65.0)
	var lane_step := _tick_step(viewer.lane_height, 40.0)
	var cell := ceilf(from.x / cell_step) * cell_step
	while cell <= to.x:
		var x: float = viewer.cell_to_screen_x(cell)
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), GRID)
		_label(Vector2(x + 3.0, 20.0), "%.1f" % cell)
		cell += cell_step
	var lane := ceilf(from.y / lane_step) * lane_step
	while lane <= to.y:
		var y: float = viewer.lane_to_y(lane)
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), GRID)
		_label(Vector2(3.0, y - 3.0), "%.1f" % lane)
		lane += lane_step
	_label(Vector2(2.0, 20.0), "C/L", INK, 12)
	# At useful zoom levels show the underlying one-cell divisions even when
	# numeric labels use a wider interval.
	if cell_step > 1.0 and viewer.cell_width_px >= 12.0:
		for i in range(int(ceilf(from.x)), int(floor(to.x)) + 1):
			var x: float = viewer.cell_to_screen_x(i)
			draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(GRID, 0.06))

func _draw_sections() -> void:
	var rect: Rect2 = viewer.get_map_rect()
	for section in viewer.visible_sections():
		if section.id == "default":
			continue
		for cell in [section.start_cell, section.end_cell]:
			var x: float = viewer.cell_to_screen_x(cell)
			if x < rect.position.x or x > rect.end.x:
				continue
			draw_dashed_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0.25, 0.8, 1.0, 0.65), 1.0, 10.0)
		var label_x := clampf(viewer.cell_to_screen_x(section.start_cell) + 8.0, rect.position.x + 8.0, rect.end.x - 90.0)
		if viewer.cell_to_screen_x(section.end_cell) >= rect.position.x and viewer.cell_to_screen_x(section.start_cell) <= rect.end.x:
			_label(Vector2(label_x, rect.position.y + 19.0), section.id.to_upper(), Color(0.25, 0.8, 1.0), 14)

func _draw_signal(entry: Dictionary) -> void:
	var data: SignalData = entry["data"]
	var position: Vector2 = viewer.cell_lane_to_screen(entry["cell"], data.lane)
	var rect: Rect2 = viewer.get_map_rect()
	var selected: bool = viewer.selected_index >= 0 and viewer.entries[viewer.selected_index] == entry
	var detection := data.detection
	if viewer.vision_toggle.button_pressed and detection != null:
		var facing := data.facing_deg
		if not detection.patrol_points.is_empty():
			facing = detection.patrol_points[0].facing_deg
		var polygon := PackedVector2Array()
		for point in detection.get_visual_polygon(viewer.cell_width_px):
			polygon.append(position + point.rotated(deg_to_rad(facing)))
		if polygon.size() >= 3:
			draw_colored_polygon(polygon, Color(1.0, 0.8, 0.2, 0.14))
			var outline := polygon.duplicate()
			outline.append(polygon[0])
			draw_polyline(outline, Color(1.0, 0.8, 0.2, 0.6), 1.0)
	if viewer.patrol_toggle.button_pressed and data.mobility != null:
		var route := PackedVector2Array()
		for point in data.mobility.patrol_points:
			var screen: Vector2 = viewer.cell_lane_to_screen(point.cell_x, point.lane)
			route.append(screen)
			draw_circle(screen, 3.0, Color(0.6, 0.8, 1.0))
			if selected:
				_label(screen + Vector2(6.0, -8.0), "%.2f / %d (%.1fs)" % [point.cell_x, point.lane, point.dwell_sec])
		if route.size() > 1:
			if data.mobility.patrol_mode == MobilityComponent.PatrolMode.LOOP:
				route.append(route[0])
			draw_polyline(route, Color(0.6, 0.8, 1.0, 0.65), 1.5)
	if not rect.has_point(position):
		return
	var color := GOLD if selected else Color(0.25, 0.9, 0.75)
	if viewer.threat_toggle != null and viewer.threat_toggle.button_pressed:
		_draw_threat_ring(position, data, selected)
	# These markers intentionally reveal even hidden/unknown authored signals.
	draw_circle(position, 7.0 if selected else 5.0, color)
	draw_circle(position, 11.0 if selected else 8.0, color, false, 1.5)
	if viewer.security_toggle.button_pressed:
		var locked := (data.puzzle != null and data.puzzle.is_locked()) or (data.type == SignalData.Type.DOOR and data.door_locked)
		if locked:
			var badge := position + Vector2(-12.0, -12.0)
			draw_colored_polygon(PackedVector2Array([badge + Vector2(0, -4), badge + Vector2(4, 0), badge + Vector2(0, 4), badge + Vector2(-4, 0)]), GOLD)
		if data.ic_modules != null and not data.ic_modules.modules.is_empty():
			draw_rect(Rect2(position + Vector2(9.0, -15.0), Vector2(7.0, 7.0)), Color(0.9, 0.5, 1.0))
	if viewer.labels_toggle.button_pressed and (viewer.zoom >= 0.12 or selected):
		var label_pos := position + Vector2(12.0, 24.0 if data.lane >= 3 else -22.0)
		var label_width := _font.get_string_size(data.system_id, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13).x
		label_pos.x = clampf(label_pos.x, rect.position.x + 3.0, maxf(rect.position.x + 3.0, rect.end.x - label_width - 5.0))
		_label(label_pos, data.system_id, color)
		if viewer.distance_toggle.button_pressed:
			_label(label_pos + Vector2(0.0, 16.0), "%.2f / %d" % [entry["cell"], data.lane], color, 12)
	if viewer.security_toggle.button_pressed and (viewer.zoom >= 0.12 or selected):
		var summary: String = viewer.security_summary(data)
		if not summary.is_empty():
			var width := _font.get_string_size(summary, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x
			var security_pos := position + Vector2(12.0, 56.0 if data.lane >= 3 else 14.0)
			security_pos.x = clampf(security_pos.x, rect.position.x + 3.0, maxf(rect.position.x + 3.0, rect.end.x - width - 5.0))
			_label(security_pos, summary, Color(0.9, 0.7, 0.95), 12)

func _draw_start_point() -> void:
	if viewer.section_index >= 0 and viewer.start_location["section_id"] != viewer.get_current_section().id:
		return
	var point: Vector2 = viewer.cell_lane_to_screen(viewer.start_position.x, viewer.start_position.y)
	if not viewer.get_map_rect().has_point(point):
		return
	var color := Color(0.5, 1.0, 0.5)
	draw_circle(point, 13.0, color, false, 2.0)
	draw_line(point - Vector2(19.0, 0.0), point + Vector2(19.0, 0.0), color, 2.0)
	draw_line(point - Vector2(0.0, 19.0), point + Vector2(0.0, 19.0), color, 2.0)
	_label(point + Vector2(20.0, -20.0), "START %.2f / %.2f" % [viewer.start_position.x, viewer.start_position.y], color)

func _draw_route_distances() -> void:
	var rect: Rect2 = viewer.get_map_rect()
	for section in viewer.visible_sections():
		if section.id == "default":
			continue
		var progress: float = section.progress_start
		var previous := Vector2(-10000.0, -10000.0)
		for i in section.path_points.size():
			if i > 0:
				progress += viewer.facility_layout.segment_length(section.path_points[i - 1], section.path_points[i])
			var point: Vector2 = viewer.cell_lane_to_screen(section.path_points[i].x, section.path_points[i].y)
			if rect.has_point(point) and point.distance_to(previous) > 65.0:
				_label(point + Vector2(4.0, 18.0), "path %.1f  %s" % [progress, viewer.format_runtime(progress)], Color(0.2, 0.8, 1.0), 12)
				previous = point

func _draw_ruler() -> void:
	var a: Vector2 = viewer.cell_lane_to_screen(viewer.measurement[0].x, viewer.measurement[0].y)
	draw_circle(a, 5.0, GOLD)
	_label(a + Vector2(8.0, -8.0), "A", GOLD)
	if viewer.measurement.size() == 2:
		var b: Vector2 = viewer.cell_lane_to_screen(viewer.measurement[1].x, viewer.measurement[1].y)
		draw_circle(b, 5.0, GOLD)
		draw_dashed_line(a, b, GOLD, 2.0, 8.0)
		_label(b + Vector2(8.0, -8.0), "B", GOLD)

# --- threat ---

static func threat_color(reach: String) -> Color:
	match reach:
		"certain": return THREAT_CERTAIN
		"possible": return THREAT_POSSIBLE
		"never": return THREAT_NEVER
	return Color(0.0, 0.0, 0.0, 0.0)

# Route stretches a signal can see, drawn along the runner's path. Possible
# coverage fades with the fraction of the cycle it is watched.
func _draw_threat_bands(entry: Dictionary) -> void:
	var data: SignalData = entry["data"]
	var report: Dictionary = viewer.reach_reports.get(data.system_id, {})
	if report.is_empty() or report["intervals"].is_empty():
		return
	var selected: bool = viewer.selected_index >= 0 and viewer.entries[viewer.selected_index] == entry
	var base := threat_color(report["reach"])
	var width := maxf(4.0, 0.35 * viewer.lane_height)
	for interval in report["intervals"]:
		var alpha := 0.55 if report["reach"] == "certain" else 0.15 + 0.4 * float(interval["max_ratio"])
		if selected:
			alpha = minf(1.0, alpha + 0.3)
		var points := PackedVector2Array()
		var progress: float = interval["from"]
		var to: float = interval["to"]
		var step := maxf(0.05, (to - progress) / 40.0)
		while true:
			var at: Vector2 = viewer.facility_layout.sample_position(minf(progress, to))
			points.append(viewer.cell_lane_to_screen(at.x, at.y))
			if progress >= to:
				break
			progress += step
		if points.size() == 1:
			points.append(points[0] + Vector2(1.0, 0.0))
		draw_polyline(points, Color(base, alpha), width)
		if selected:
			_label(points[0] + Vector2(0.0, -width), "%s %d%%" % [data.system_id, int(round(float(interval["max_ratio"]) * 100.0))], base, 12)

func _draw_threat_ring(position: Vector2, data: SignalData, selected: bool) -> void:
	var report: Dictionary = viewer.reach_reports.get(data.system_id, {})
	if report.is_empty():
		return
	var color := threat_color(report["reach"])
	if color.a <= 0.0:
		return
	var radius := 15.0 if selected else 12.0
	if report["reach"] == "never":
		draw_arc(position, radius, 0.0, TAU, 24, Color(color, 0.7), 1.5)
	else:
		draw_arc(position, radius, 0.0, TAU, 24, color, 2.5)
		if report["reach"] == "possible":
			_label(position + Vector2(-radius - 34.0, 5.0), "%d%%" % int(round(float(report["hit_walk"]) * 100.0)), color, 11)
