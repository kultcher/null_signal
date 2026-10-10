extends RunDefinition

# Prop gallery: every WireframeModels entry laid out along a long hall so you
# can eyeball the library in-game. Point RunManager.level_script_path here.
# No signals, escalation off. The first bay shows the four rotations.

const SPACING := 1.25
const START_CELL := 3.2

func get_run_id() -> String:
	return "prop_gallery"

func is_escalation_enabled() -> bool:
	return false

func _model_names() -> Array:
	var names := WireframeModels.get_model_names()
	names.sort_custom(func(a, b) -> bool: return String(a) < String(b))
	return names

func get_rooms() -> Array[FacilityRoom]:
	var names := _model_names()
	var end_cell := START_CELL + SPACING * (ceilf(names.size() / 2.0) + 2.0)
	var hall := room("gallery", -1.0, end_cell).label("PROP GALLERY").lanes(-0.6, 4.6)

	# Rotation demo: a car in each orientation.
	for rot in 4:
		hall.place(&"car", 0.3 + rot * 0.6, 1.0 if rot % 2 == 0 else 3.0, rot)

	# Two rows of models (top and bottom), name tags under each.
	for i in names.size():
		var model: StringName = names[i]
		var cell := START_CELL + SPACING * float(i / 2)
		var lane := 0.4 if i % 2 == 0 else 3.4
		hall.place(model, cell, lane)
		hall.prop(cell - 0.5, cell + 0.5, lane + 0.75, lane + 1.0, String(model))
	return [hall.build()]
