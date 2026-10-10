class_name FuzzPuzzleConfig extends Resource

@export_group("Packets")
@export_range(0, 100, 1) var starting_ammo: int = 5
@export_range(1, 100, 1) var max_ammo: int = 5
@export_range(0, 100, 0.1) var regeneration_per_second: float = 1.0
@export_range(0.01, 10, 0.01) var flight_time_sec: float = 0.5

@export_group("Scoring")
@export_range(0, 360, 1) var sweet_spot_arc_deg: float = 30.0
@export_range(0.01, 10000, 1) var target_points: float = 100.0
@export_range(0.01, 1000, 1) var direct_hit_points: float = 20.0
@export_range(0, 100, 0.1) var falloff_points: float = 2.0
@export_range(0.01, 180, 0.1) var falloff_step_deg: float = 5.0
@export_range(0, 1000, 0.1) var decay_points_per_second: float = 0.0

@export_group("Impact feedback")
@export_range(0, 30, 0.1) var impact_hold_sec: float = 2.5
@export_range(0, 30, 0.1) var impact_fade_sec: float = 2.5
@export_range(1, 90, 1) var impact_arc_deg: float = 10.0
@export var neutral_color: Color = Color.WHITE
@export var direct_color: Color = Color(1.0, 0.12, 0.08)
@export var medium_color: Color = Color(1.0, 0.5, 0.05)
@export var weak_color: Color = Color(1.0, 0.95, 0.15)

@export_group("Difficulty")
## Optional complete profiles for difficulty 2, 3, etc. The last profile is
## reused beyond the authored list. Empty means the base values at every level.
@export var higher_difficulty_profiles: Array[Resource] = [] # FuzzPuzzleConfig resources.

func for_difficulty(level: int) -> FuzzPuzzleConfig:
	var selected: FuzzPuzzleConfig = self
	if level > 1 and not higher_difficulty_profiles.is_empty():
		var profile := higher_difficulty_profiles[mini(level - 2, higher_difficulty_profiles.size() - 1)] as FuzzPuzzleConfig
		if profile != null:
			selected = profile
	return selected.normalized_copy()

func normalized_copy() -> FuzzPuzzleConfig:
	var copy := duplicate(true) as FuzzPuzzleConfig
	copy.max_ammo = maxi(1, max_ammo)
	copy.starting_ammo = clampi(starting_ammo, 0, copy.max_ammo)
	copy.regeneration_per_second = maxf(0.0, regeneration_per_second)
	copy.flight_time_sec = maxf(0.01, flight_time_sec)
	copy.sweet_spot_arc_deg = clampf(sweet_spot_arc_deg, 0.0, 360.0)
	copy.target_points = maxf(0.01, target_points)
	copy.direct_hit_points = maxf(0.01, direct_hit_points)
	copy.falloff_points = maxf(0.0, falloff_points)
	copy.falloff_step_deg = maxf(0.01, falloff_step_deg)
	copy.decay_points_per_second = maxf(0.0, decay_points_per_second)
	copy.impact_hold_sec = maxf(0.0, impact_hold_sec)
	copy.impact_fade_sec = maxf(0.0, impact_fade_sec)
	copy.impact_arc_deg = clampf(impact_arc_deg, 1.0, 90.0)
	return copy

func points_at_offset(offset_deg: float) -> float:
	var outside := maxf(0.0, absf(offset_deg) - sweet_spot_arc_deg * 0.5)
	return maxf(0.0, direct_hit_points - outside / falloff_step_deg * falloff_points)

func impact_color(points: float, age: float) -> Color:
	var strength := clampf(points / direct_hit_points, 0.0, 1.0)
	var tint := weak_color.lerp(medium_color, strength * 2.0) if strength < 0.5 else medium_color.lerp(direct_color, (strength - 0.5) * 2.0)
	var fade := 0.0
	if age > impact_hold_sec:
		fade = 1.0 if impact_fade_sec <= 0.0 else clampf((age - impact_hold_sec) / impact_fade_sec, 0.0, 1.0)
	return tint.lerp(neutral_color, fade)
