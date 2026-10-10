class_name GauntletSampler extends RefCounted

const MAX_MATRIX := 512
var settings: GauntletSettings
var rng := RandomNumberGenerator.new()
var matrix: Array[Dictionary] = []
var bag: Array[Dictionary] = []
var sampled_combinations := false

func configure(values: GauntletSettings) -> void:
	settings = values.normalized_copy()
	rng.seed = settings.shuffle_seed
	matrix.clear()
	bag.clear()
	sampled_combinations = false
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

func next_case() -> Dictionary:
	if bag.is_empty():
		if sampled_combinations:
			matrix.clear()
			if settings.include_baseline:
				matrix.append(_case())
			for i in MAX_MATRIX:
				matrix.append(_random_case())
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
