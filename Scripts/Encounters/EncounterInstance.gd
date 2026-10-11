# EncounterInstance.gd
# One generated placement of an EncounterTemplate: the spawns it produced
# (RunDefinition spawn dictionaries, ready for get_spawns()), which role each
# signal plays, the wildcard that was rolled, and where the runner may stop.
class_name EncounterInstance extends RefCounted

var template_id: StringName
var label: String = ""
var prefix: String = ""
var anchor_cell: float = 0.0
var start_cell: float = 0.0
var end_cell: float = 0.0
var route_lane: int = 2
var flipped := false

var spawns: Array[Dictionary] = []
var roles: Dictionary = {}            # system_id -> role
var wildcard: Dictionary = {}         # empty when the template has none
# Points where the runner waits: {"cell", "lane", "kind"}. "blocker" = the
# obstacle stops him (locked door, hazard). Reserved kinds: "cover".
var stop_points: Array[Dictionary] = []

func get_length() -> float:
	return end_cell - start_cell

# Adds a spawn under a role; the system_id is "<prefix>_<role>".
func add(role: String, builder: RunDefinition.SpawnBuilder) -> String:
	var system_id := "%s_%s" % [prefix, role]
	spawns.append(builder.id(system_id).build())
	roles[system_id] = role
	return system_id

func ids_with_role(role_prefix: String) -> Array[String]:
	var result: Array[String] = []
	for system_id in roles:
		if String(roles[system_id]).begins_with(role_prefix):
			result.append(system_id)
	return result

func describe() -> String:
	var text := label
	if not wildcard.is_empty():
		var parts: Array[String] = []
		for key in wildcard:
			if key != "kind":
				parts.append("%s %s" % [key, str(wildcard[key])])
		text += " // wildcard %s (%s)" % [wildcard.get("kind", "?"), ", ".join(parts)]
	return text
