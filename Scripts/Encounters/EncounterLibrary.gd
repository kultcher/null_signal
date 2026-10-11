# EncounterLibrary.gd
# The standard encounter templates, by id. Returns fresh instances so callers
# can tweak exports (difficulty, pools) without touching shared state.
class_name EncounterLibrary extends RefCounted

const IDS: Array[StringName] = [&"watched_door", &"camera_corridor", &"drone_patrol", &"guard_patrol"]

static func make(template_id: StringName, difficulty: int = 1) -> EncounterTemplate:
	var template: EncounterTemplate
	match template_id:
		&"watched_door": template = WatchedDoorTemplate.new()
		&"camera_corridor": template = CameraCorridorTemplate.new()
		&"drone_patrol": template = DronePatrolTemplate.new()
		&"guard_patrol": template = GuardPatrolTemplate.new()
		_:
			push_error("EncounterLibrary: unknown template %s" % template_id)
			return null
	template.difficulty = difficulty
	return template

static func all(difficulty: int = 1) -> Array[EncounterTemplate]:
	var result: Array[EncounterTemplate] = []
	for template_id in IDS:
		result.append(make(template_id, difficulty))
	return result
