# FacilityRoom.gd
# One room (or outdoor area) of a facility map.
# Rooms are authored in path space: x in cells along the runner's path,
# y in lanes (lane 0 = top, LANES-1 = bottom). Edges may sit between lanes,
# e.g. lane_top = -0.5 puts the wall half a lane above lane 0.

class_name FacilityRoom extends RefCounted

enum Kind { ROOM, EXTERIOR }

var id: String = ""
var label: String = ""
var kind: Kind = Kind.ROOM
var start_cell: float = 0.0
var end_cell: float = 0.0
var lane_top: float = -0.5
var lane_bottom: float = 4.5

# Gaps in the top/bottom walls, as {"side": "top"/"bottom", "from_cell": f, "to_cell": f}.
var wall_openings: Array[Dictionary] = []

# Purely visual furniture/fixtures, as {"rect": Rect2 (cells x lanes), "label": String}.
var props: Array[Dictionary] = []

func contains(cell: float, lane_pos: float) -> bool:
	return cell >= start_cell and cell <= end_cell and lane_pos >= lane_top and lane_pos <= lane_bottom

func is_exterior() -> bool:
	return kind == Kind.EXTERIOR

func get_rect() -> Rect2:
	return Rect2(start_cell, lane_top, end_cell - start_cell, lane_bottom - lane_top)
