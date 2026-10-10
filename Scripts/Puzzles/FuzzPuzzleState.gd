class_name FuzzPuzzleState extends RefCounted

var config: FuzzPuzzleConfig
var ammo := 0
var progress := 0.0
var sweet_spot_angle := 0.0
var solved := false
var packets: Array[Dictionary] = []
var _regeneration := 0.0

func reset(settings: FuzzPuzzleConfig, fixed_angle_deg: float = -1.0) -> void:
	config = settings.normalized_copy()
	ammo = config.starting_ammo
	progress = 0.0
	solved = false
	packets.clear()
	_regeneration = 0.0
	sweet_spot_angle = randf() * TAU if fixed_angle_deg < 0.0 else deg_to_rad(fixed_angle_deg)

func fire(angle: float) -> bool:
	if solved or ammo <= 0:
		return false
	ammo -= 1
	packets.append({"angle": angle, "remaining": config.flight_time_sec})
	return true

func points_for_angle(angle: float) -> float:
	var offset := absf(rad_to_deg(wrapf(angle - sweet_spot_angle, -PI, PI)))
	return config.points_at_offset(offset)

func advance(delta: float) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	if solved or delta <= 0.0:
		return hits
	# Regeneration has no banked credit while capped.
	if ammo < config.max_ammo:
		_regeneration += delta * config.regeneration_per_second
		var gained := floori(_regeneration)
		ammo = mini(config.max_ammo, ammo + gained)
		_regeneration -= gained
	if ammo == config.max_ammo:
		_regeneration = 0.0
	# Apply decay between impact times, including on slow frames.
	var elapsed := 0.0
	var ordered := packets.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["remaining"] < b["remaining"])
	for packet in ordered:
		var impact_time: float = maxf(0.0, packet["remaining"])
		packet["remaining"] -= delta
		if packet["remaining"] > 0.000001:
			continue
		impact_time = minf(delta, impact_time)
		progress = maxf(0.0, progress - config.decay_points_per_second * (impact_time - elapsed))
		elapsed = impact_time
		packets.erase(packet)
		var points := points_for_angle(packet["angle"])
		hits.append({"angle": packet["angle"], "points": points, "age": maxf(0.0, -packet["remaining"])})
		progress = minf(config.target_points, progress + points)
		if progress >= config.target_points:
			solved = true
			packets.clear()
			break
	if not solved:
		progress = maxf(0.0, progress - config.decay_points_per_second * (delta - elapsed))
	return hits
