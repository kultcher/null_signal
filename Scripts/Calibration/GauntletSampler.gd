class_name GauntletSampler extends RefCounted

const MAX_MATRIX := 512
var settings: GauntletSettings
var rng := RandomNumberGenerator.new()
var matrix: Array[Dictionary] = []
var bag: Array[Dictionary] = []
var sampled_combinations := false
var encounter_matrix: Array[Dictionary] = []
var encounter_bag: Array[Dictionary] = []

func configure(values: GauntletSettings) -> void:
	settings = values.normalized_copy()
	rng.seed = settings.shuffle_seed
	matrix.clear()
	bag.clear()
	encounter_bag.clear()
	sampled_combinations = false
	if settings.trial_source == "encounters":
		_build_encounters()
		return
	if settings.include_baseline:
		matrix.append(_case())
	if settings.isolated_elements:
		if settings.ic_count > 0:
			for key in settings.ic_pool:
				for level in range(settings.ic_min, settings.ic_max + 1):
					matrix.append(_case([{ "ic": key, "difficulty": level }]))
		if settings.puzzle_enabled:
			for key in settings.puzzle_pool:
				for level in range(settings.puzzle_min, settings.puzzle_max + 1):
					matrix.append(_case([], key, level))
	else:
		var count := settings.ic_count
		var choices := 1.0
		for i in count:
			choices *= float(settings.ic_pool.size() - i) / float(i + 1)
		choices *= pow(settings.ic_max - settings.ic_min + 1, count)
		if settings.puzzle_enabled:
			choices *= settings.puzzle_pool.size() * (settings.puzzle_max - settings.puzzle_min + 1)
		if choices <= MAX_MATRIX:
			if settings.ic_count > 0 or settings.puzzle_enabled or not settings.include_baseline:
				_expand_ic([], 0)
		else:
			sampled_combinations = true
			for i in MAX_MATRIX:
				matrix.append(_random_case())
	if matrix.is_empty():
		matrix.append(_case())
	matrix = _with_leads(matrix)
	_build_encounters()

func next_case() -> Dictionary:
	if bag.is_empty():
		if sampled_combinations:
			matrix.clear()
			if settings.include_baseline:
				matrix.append(_case())
			for i in MAX_MATRIX:
				matrix.append(_random_case())
			matrix = _with_leads(matrix)
		bag = matrix.duplicate(true)
		for i in range(bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var swap := bag[i]
			bag[i] = bag[j]
			bag[j] = swap
	return bag.pop_back()

func _expand_ic(modules: Array, start: int) -> void:
	if modules.size() == settings.ic_count:
		if settings.puzzle_enabled:
			for key in settings.puzzle_pool:
				for level in range(settings.puzzle_min, settings.puzzle_max + 1):
					matrix.append(_case(modules, key, level))
		else:
			matrix.append(_case(modules))
		return
	for i in range(start, settings.ic_pool.size()):
		for level in range(settings.ic_min, settings.ic_max + 1):
			var expanded := modules.duplicate(true)
			expanded.append({"ic": settings.ic_pool[i], "difficulty": level})
			_expand_ic(expanded, i + 1)

func _random_case() -> Dictionary:
	var available := Array(settings.ic_pool)
	var modules: Array = []
	for i in settings.ic_count:
		var index := rng.randi_range(0, available.size() - 1)
		modules.append({"ic": available[index], "difficulty": rng.randi_range(settings.ic_min, settings.ic_max)})
		available.remove_at(index)
	modules.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ic < b.ic)
	var key := settings.puzzle_pool[rng.randi_range(0, settings.puzzle_pool.size() - 1)] if settings.puzzle_enabled else "none"
	return _case(modules, key, rng.randi_range(settings.puzzle_min, settings.puzzle_max) if settings.puzzle_enabled else 0)

func _case(modules: Array = [], puzzle: String = "none", difficulty: int = 0) -> Dictionary:
	return {"ic": modules.duplicate(true), "puzzle": puzzle, "difficulty": difficulty}

# Window sweep: every case runs at every configured lead distance (-1 = the
# screen edge when none are configured).
func _with_leads(cases: Array[Dictionary]) -> Array[Dictionary]:
	var leads: Array = Array(settings.lead_cells) if not settings.lead_cells.is_empty() else [-1.0]
	var result: Array[Dictionary] = []
	for case in cases:
		for lead in leads:
			var copy := case.duplicate(true)
			copy["lead"] = float(lead)
			result.append(copy)
	return result

func _build_encounters() -> void:
	encounter_matrix.clear()
	var leads: Array = Array(settings.lead_cells) if not settings.lead_cells.is_empty() else [-1.0]
	var variants: Array[Dictionary] = [_case()]
	var with_disruptions := settings.trial_source == "encounters" and settings.encounter_disruptions
	if with_disruptions:
		# Reuse the bounded element sampler for IC-only variants. Disable this
		# option on the nested sampler, so it never recurses into modifiers.
		var values := settings.duplicate(true) as GauntletSettings
		values.trial_source = "elements"
		values.encounter_disruptions = false
		values.ic_pool = settings.encounter_ic_pool()
		values.puzzle_enabled = false
		values.lead_cells = PackedFloat32Array()
		values.shuffle_seed = rng.randi()
		var modifiers := GauntletSampler.new()
		modifiers.configure(values)
		variants = modifiers.matrix
		sampled_combinations = modifiers.sampled_combinations
	for template in settings.encounter_pool:
		for lead in leads:
			for variant in variants:
				var entry := {"template": template, "lead": float(lead)}
				if with_disruptions:
					entry["ic"] = variant.ic.duplicate(true)
				encounter_matrix.append(entry)

# Shuffled bag of template x lead; each draw gets its own generation seed so a
# repeat can rebuild the exact same placement.
func next_encounter() -> Dictionary:
	if encounter_bag.is_empty():
		if settings.encounter_disruptions:
			_build_encounters()
		encounter_bag = encounter_matrix.duplicate(true)
		for i in range(encounter_bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var swap := encounter_bag[i]
			encounter_bag[i] = encounter_bag[j]
			encounter_bag[j] = swap
	var case: Dictionary = encounter_bag.pop_back()
	case["seed"] = rng.randi()
	return case
