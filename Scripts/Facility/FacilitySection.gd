# FacilitySection.gd
# One "feed" of the facility map: a stretch of the runner's route shown in a
# single framed view. The camera follows the runner inside a section and holds
# once the section's end is on screen; moving to the next section is a hard cut.
#
# Coordinates are the map's cell (x) / lane (y) space. Sections own disjoint
# cell ranges [start_cell, end_cell): signals belong to the section their spawn
# cell falls in and are only shown while that section is active.

class_name FacilitySection extends RefCounted

var id: String = ""
var label: String = ""
var start_cell: float = 0.0
var end_cell: float = 0.0

# Runner route through this section, in (cell, lane) points.
var path_points: PackedVector2Array = PackedVector2Array()

# Filled in by FacilityLayout: path length (in cells) before this section
# starts, and this section's own path length.
var progress_start: float = 0.0
var path_length: float = 0.0

func contains_cell(cell: float) -> bool:
	return cell >= start_cell and cell < end_cell

func get_progress_end() -> float:
	return progress_start + path_length
