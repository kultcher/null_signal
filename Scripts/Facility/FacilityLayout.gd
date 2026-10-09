# FacilityLayout.gd
# Spatial description of a run: the rooms the runner's path passes through.
# For now the path is a straight line along TimelineManager.path_lane, so
# progress along the path is simply the cell position. Branching paths
# (shortcuts through unlocked doors) should extend this class rather than
# leak into callers.

class_name FacilityLayout extends RefCounted

var rooms: Array[FacilityRoom] = []

func _init(room_list: Array[FacilityRoom] = []) -> void:
	rooms = room_list
	rooms.sort_custom(func(a: FacilityRoom, b: FacilityRoom) -> bool: return a.start_cell < b.start_cell)

func has_rooms() -> bool:
	return not rooms.is_empty()

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

# Distance along the runner's path to the point where it passes closest to
# (cell, lane). Straight path: just the cell.
func project_to_path(cell: float, _lane_pos: float) -> float:
	return cell
