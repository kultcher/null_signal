extends RunDefinition

# Encounter gallery: the standard encounter templates strung along a straight
# hall, with a watched door as the transition between sections. Browse it in
# the level viewer (F2, Threat on) or point RunManager.level_script_path here to
# play it. Change SEED (or set NULL_ENCOUNTER_SEED) to roll new wildcards and
# mirroring; each encounter's flavor dot describes what was rolled.

const SEED := 1
const ORDER: Array[StringName] = [
	&"camera_corridor", &"watched_door",
	&"drone_patrol", &"watched_door",
	&"guard_patrol", &"watched_door",
]
const GAP_CELLS := 1.0
const START_CELL := 1.0
const EXIT_CELLS := 4.0
const BOUNDARY_PAST_DOOR := 0.2

var instances: Array[EncounterInstance] = []
var _door_cells: Array[float] = []
var _end_cell := 0.0
var _planned := false

func get_run_id() -> String:
	return "encounter_gallery"

func get_display_name() -> String:
	return "Encounter gallery (seed %d)" % get_seed()

func is_escalation_enabled() -> bool:
	return false

func get_seed() -> int:
	var env := OS.get_environment("NULL_ENCOUNTER_SEED")
	return int(env) if env.is_valid_int() else SEED

func _plan() -> void:
	if _planned:
		return
	_planned = true
	var rng := RandomNumberGenerator.new()
	rng.seed = get_seed()
	var cursor := START_CELL
	for i in ORDER.size():
		var template := EncounterLibrary.make(ORDER[i])
		var inst := template.generate(self, cursor, rng, "%s_%d" % [String(ORDER[i]).get_slice("_", 0), i])
		instances.append(inst)
		if template is WatchedDoorTemplate:
			_door_cells.append((template as WatchedDoorTemplate).get_door_cell(cursor))
		cursor = inst.end_cell + GAP_CELLS
	_end_cell = cursor + EXIT_CELLS

func get_sections() -> Array[FacilitySection]:
	_plan()
	var result: Array[FacilitySection] = []
	var start := -1.0
	var bounds: Array[float] = []
	for door in _door_cells:
		bounds.append(door + BOUNDARY_PAST_DOOR)
	bounds.append(_end_cell)
	for i in bounds.size():
		var end := bounds[i]
		var points: Array[Vector2] = [Vector2(start, 2.0), Vector2(end, 2.0)]
		result.append(section("zone_%d" % (i + 1), start, end).label(_zone_label(start, end)).path(points).build())
		start = end
	return result

func get_rooms() -> Array[FacilityRoom]:
	_plan()
	var result: Array[FacilityRoom] = []
	var start := -1.0
	var bounds: Array[float] = _door_cells.duplicate()
	bounds.append(_end_cell)
	for i in bounds.size():
		var end := bounds[i]
		result.append(room("hall_%d" % (i + 1), start, end).label(_zone_label(start, end)).lanes(-0.5, 4.5).build())
		start = end
	return result

func get_spawns() -> Array[Dictionary]:
	_plan()
	var result: Array[Dictionary] = []
	for inst in instances:
		result.append_array(inst.spawns)
	return result

func get_flavor() -> Array[Dictionary]:
	_plan()
	var result: Array[Dictionary] = []
	for inst in instances:
		result.append(flavor(inst.anchor_cell + 0.3, -0.2, inst.describe()))
	return result

# Name each zone after the non-door encounters it contains.
func _zone_label(start: float, end: float) -> String:
	var names: Array[String] = []
	for inst in instances:
		if inst.template_id != &"watched_door" and inst.anchor_cell >= start and inst.anchor_cell < end:
			names.append(inst.label)
	return " + ".join(names) if not names.is_empty() else "EXIT"
