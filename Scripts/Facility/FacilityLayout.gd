# FacilityLayout.gd
# Spatial description of a run: the rooms on the map and the runner's route,
# split into sections (one framed feed each).
#
# Progress along the route is measured in cells of path length, so the
# runner's speed is the same whichever way the path turns. Lane offsets are
# converted to cell-equivalent length using lane_to_cell_scale (lane spacing /
# cell width in pixels), which TimelineManager keeps up to date.

class_name FacilityLayout extends RefCounted

const DEFAULT_PATH_LANE := 2.0
# Half-length of the default straight route. Kept modest so positions along
# it stay precise.
const DEFAULT_EXTENT := 10000.0

var rooms: Array[FacilityRoom] = []
var sections: Array[FacilitySection] = []
# Flavor objects: purely descriptive map annotations (a small grey dot with a
# line of hover text). Not signals: no scan, connect, IC or detection.
# Each is {"cell", "lane", "text", "model", "rot"}; see RunDefinition.flavor().
var flavor: Array[Dictionary] = []
var lane_to_cell_scale: float = 0.375

func _init(room_list: Array[FacilityRoom] = [], section_list: Array[FacilitySection] = []) -> void:
	rooms = room_list
	rooms.sort_custom(func(a: FacilityRoom, b: FacilityRoom) -> bool: return a.start_cell < b.start_cell)
	sections = section_list
	if sections.is_empty():
		sections = [_make_default_section()]
	sections.sort_custom(func(a: FacilitySection, b: FacilitySection) -> bool: return a.start_cell < b.start_cell)
	_assign_rooms_to_sections()
	_recompute_lengths()

# Straight route along DEFAULT_PATH_LANE, one section covering everything.
# This reproduces the original timeline behaviour.
static func _make_default_section() -> FacilitySection:
	var section := FacilitySection.new()
	section.id = "default"
	section.start_cell = -DEFAULT_EXTENT
	section.end_cell = DEFAULT_EXTENT
	section.path_points = PackedVector2Array([
		Vector2(-DEFAULT_EXTENT, DEFAULT_PATH_LANE),
		Vector2(DEFAULT_EXTENT, DEFAULT_PATH_LANE),
	])
	return section

func set_lane_to_cell_scale(scale: float) -> void:
	if is_equal_approx(scale, lane_to_cell_scale):
		return
	lane_to_cell_scale = scale
	_recompute_lengths()

# Where `progress` falls on the route, independent of the lane scale:
# {section, segment, t}. Used to keep the runner in place when the scale (and
# so every diagonal/vertical segment length) changes.
func locate_progress(progress: float) -> Dictionary:
	var section_index := get_section_index_for_progress(progress)
	var section: FacilitySection = sections[section_index]
	var points := section.path_points
	var remaining := maxf(0.0, progress - section.progress_start)
	for i in range(points.size() - 1):
		var seg_len := segment_length(points[i], points[i + 1])
		if remaining <= seg_len or i == points.size() - 2:
			var t := 0.0 if seg_len <= 0.0 else clampf(remaining / seg_len, 0.0, 1.0)
			return {"section": section_index, "segment": i, "t": t}
		remaining -= seg_len
	return {"section": section_index, "segment": 0, "t": 0.0}

# Inverse of locate_progress() under the current scale.
func progress_from_location(location: Dictionary) -> float:
	var section_index := clampi(int(location.get("section", 0)), 0, sections.size() - 1)
	var section: FacilitySection = sections[section_index]
	var points := section.path_points
	var segment := int(location.get("segment", 0))
	var progress := section.progress_start
	for i in range(mini(segment, points.size() - 1)):
		progress += segment_length(points[i], points[i + 1])
	if segment < points.size() - 1:
		progress += segment_length(points[segment], points[segment + 1]) * float(location.get("t", 0.0))
	return progress

func has_rooms() -> bool:
	return not rooms.is_empty()

# --- rooms ---

func get_room_at(cell: float, lane_pos: float) -> FacilityRoom:
	for room in rooms:
		if room.contains(cell, lane_pos):
			return room
	return null

func get_room_by_id(room_id: String) -> FacilityRoom:
	for room in rooms:
		if room.id == room_id:
			return room
	return null

func get_rooms_in_range(from_cell: float, to_cell: float) -> Array[FacilityRoom]:
	var result: Array[FacilityRoom] = []
	for room in rooms:
		if room.end_cell >= from_cell and room.start_cell <= to_cell:
			result.append(room)
	return result

func get_rooms_in_section(section: FacilitySection) -> Array[FacilityRoom]:
	var result: Array[FacilityRoom] = []
	for room in rooms:
		if room.section_id == section.id:
			result.append(room)
	return result

func _assign_rooms_to_sections() -> void:
	for room in rooms:
		if not room.section_id.is_empty():
			continue
		var section := get_section_for_cell((room.start_cell + room.end_cell) * 0.5)
		room.section_id = section.id

# --- flavor ---

# Flavor objects belong to the section their cell falls in, like signals.
func get_flavor_in_section(section: FacilitySection) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in flavor:
		if get_section_for_cell(float(item["cell"])) == section:
			result.append(item)
	return result

# --- sections ---

func get_section_for_cell(cell: float) -> FacilitySection:
	for section in sections:
		if section.contains_cell(cell):
			return section
	if cell < sections.front().start_cell:
		return sections.front()
	return sections.back()

func get_section_index_for_progress(progress: float) -> int:
	for i in range(sections.size()):
		if progress < sections[i].get_progress_end():
			return i
	return sections.size() - 1

# --- path ---

func get_total_length() -> float:
	var last: FacilitySection = sections.back()
	return last.get_progress_end()

# Runner position (cell, lane) at a given distance along the route.
func sample_position(progress: float) -> Vector2:
	var section: FacilitySection = sections[get_section_index_for_progress(progress)]
	return _sample_section(section, progress - section.progress_start)

# First progress value at which the route reaches `cell` on the x axis.
# Used to place the runner at a cell (debug stages, tests).
func progress_at_cell(cell: float) -> float:
	for section in sections:
		var points := section.path_points
		var walked := section.progress_start
		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i + 1]
			var seg_len := segment_length(a, b)
			if (cell >= minf(a.x, b.x) and cell <= maxf(a.x, b.x)) and not is_equal_approx(a.x, b.x):
				var t := (cell - a.x) / (b.x - a.x)
				return walked + (seg_len * clampf(t, 0.0, 1.0))
			if is_equal_approx(a.x, cell):
				return walked
			walked += seg_len
	if cell < sections.front().path_points[0].x:
		return 0.0
	return get_total_length()

# Distance along the path from the runner's current progress to the point
# where the route passes closest to (cell, lane). Only considers the section
# that owns `cell`.
func project_to_path(cell: float, lane_pos: float) -> float:
	var section := get_section_for_cell(cell)
	var target := _to_metric(Vector2(cell, lane_pos))
	var best_dist := INF
	var best_progress := section.progress_start
	var walked := section.progress_start
	var points := section.path_points
	for i in range(points.size() - 1):
		var a := _to_metric(points[i])
		var b := _to_metric(points[i + 1])
		var closest := Geometry2D.get_closest_point_to_segment(target, a, b)
		var dist := closest.distance_to(target)
		if dist < best_dist:
			best_dist = dist
			best_progress = walked + a.distance_to(closest)
		walked += a.distance_to(b)
	return best_progress

func _sample_section(section: FacilitySection, local_progress: float) -> Vector2:
	var points := section.path_points
	if points.is_empty():
		return Vector2(0.0, DEFAULT_PATH_LANE)
	var remaining := maxf(0.0, local_progress)
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var seg_len := segment_length(a, b)
		if remaining <= seg_len or i == points.size() - 2:
			if seg_len <= 0.0:
				return b
			# Interpolate in 64-bit floats: Vector2 is 32-bit, and on long
			# segments (e.g. the default straight route) Vector2.lerp rounds the
			# position to coarse steps, so the runner moves in visible jerks.
			var t := clampf(remaining / seg_len, 0.0, 1.0)
			return Vector2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
		remaining -= seg_len
	return points[points.size() - 1]

func _recompute_lengths() -> void:
	var walked := 0.0
	for section in sections:
		section.progress_start = walked
		var length := 0.0
		for i in range(section.path_points.size() - 1):
			length += segment_length(section.path_points[i], section.path_points[i + 1])
		section.path_length = length
		walked += length

# Path length (cells) between two (cell, lane) points.
func segment_length(a: Vector2, b: Vector2) -> float:
	return _to_metric(a).distance_to(_to_metric(b))

# (cell, lane) -> uniform units (cells) so diagonal/vertical moves cost real distance.
func _to_metric(point: Vector2) -> Vector2:
	return Vector2(point.x, point.y * lane_to_cell_scale)
