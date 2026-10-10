class_name GauntletSettings extends Resource

# These modules can affect a single door without additional targets.
const DOOR_IC := ["bouncer", "callback", "faraday", "haze", "trace", "shy", "siphon"]
const PUZZLES := ["sniff", "decrypt", "fuzz"]

@export var tester := "tester"
@export var skill_tag := "unspecified"
@export var shuffle_seed: int = 1
@export var isolated_elements := true
@export var include_baseline := true
@export_range(0, 7, 1) var ic_count := 1
@export_range(1, 20, 1) var ic_min := 1
@export_range(1, 20, 1) var ic_max := 1
@export var ic_pool: PackedStringArray = PackedStringArray(DOOR_IC)
@export var puzzle_enabled := true
@export_range(1, 20, 1) var puzzle_min := 1
@export_range(1, 20, 1) var puzzle_max := 1
@export var puzzle_pool: PackedStringArray = PackedStringArray(PUZZLES)
@export_range(0.1, 30, 0.1) var breach_delay_sec := 3.0
@export_range(0, 10, 0.1) var next_delay_sec := 1.0
@export_range(0.01, 2, 0.01) var runner_speed := 0.15
@export var reset_heat_each_trial := true
@export var fuzz_config: FuzzPuzzleConfig

func normalized_copy() -> GauntletSettings:
	var copy := duplicate(true) as GauntletSettings
	copy.ic_pool = PackedStringArray()
	for key in ic_pool:
		if key in DOOR_IC and not key in copy.ic_pool:
			copy.ic_pool.append(key)
	copy.puzzle_pool = PackedStringArray()
	for key in puzzle_pool:
		if key in PUZZLES and not key in copy.puzzle_pool:
			copy.puzzle_pool.append(key)
	copy.ic_count = clampi(ic_count, 0, copy.ic_pool.size())
	copy.ic_min = clampi(ic_min, 1, 20)
	copy.ic_max = clampi(ic_max, copy.ic_min, 20)
	copy.puzzle_min = clampi(puzzle_min, 1, 20)
	copy.puzzle_max = clampi(puzzle_max, copy.puzzle_min, 20)
	copy.puzzle_enabled = puzzle_enabled and not copy.puzzle_pool.is_empty()
	copy.breach_delay_sec = maxf(0.1, breach_delay_sec)
	copy.next_delay_sec = maxf(0.0, next_delay_sec)
	copy.runner_speed = maxf(0.01, runner_speed)
	return copy
