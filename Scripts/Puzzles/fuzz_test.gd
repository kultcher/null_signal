extends Control

## Editable in the Inspector; runtime controls are copied from this resource.
@export var config: FuzzPuzzleConfig
@export_range(1, 20, 1) var difficulty: int = 1
@export_range(-1, 360, 1) var fixed_sweet_spot_deg: float = -1.0
@export var reveal_sweet_spot := false

@onready var puzzle: FuzzPuzzle = $Layout/Play/Puzzle
@onready var knobs: GridContainer = $Layout/Tuning/Scroll/Fields/Knobs
@onready var reveal: CheckButton = $Layout/Tuning/Scroll/Fields/Reveal
@onready var angle: SpinBox = $Layout/Tuning/Scroll/Fields/Angle
@onready var level: SpinBox = $Layout/Tuning/Scroll/Fields/Difficulty

const KEYS := ["starting_ammo", "max_ammo", "regeneration_per_second", "flight_time_sec", "sweet_spot_arc_deg", "target_points", "direct_hit_points", "falloff_points", "falloff_step_deg", "decay_points_per_second", "impact_hold_sec", "impact_fade_sec", "impact_arc_deg"]

func _ready() -> void:
	if config == null:
		config = FuzzPuzzleConfig.new()
	_load_controls()
	angle.value = fixed_sweet_spot_deg
	level.value = difficulty
	reveal.button_pressed = reveal_sweet_spot
	reveal.toggled.connect(func(value: bool): puzzle.show_sweet_spot = value)
	level.value_changed.connect(func(value: float): difficulty = int(value); _load_controls())
	$Layout/Tuning/Scroll/Fields/Apply.pressed.connect(apply_and_restart)
	$Layout/Tuning/Scroll/Fields/Reset.pressed.connect(func(): config = FuzzPuzzleConfig.new(); difficulty = 1; level.value = 1; _load_controls(); apply_and_restart())
	puzzle.puzzle_solved.connect(func(): $Layout/Play/Result.text = "SOLVED // Change settings and restart to try another profile.")
	apply_and_restart()

func _load_controls() -> void:
	var effective := config.for_difficulty(difficulty)
	for key in KEYS:
		knobs.get_node(key).value = effective.get(key)

func apply_and_restart() -> void:
	var effective := config.for_difficulty(difficulty)
	for key in KEYS:
		effective.set(key, knobs.get_node(key).value)
	puzzle.reset_puzzle(effective, angle.value)
	puzzle.show_sweet_spot = reveal.button_pressed
	$Layout/Play/Result.text = "First click focuses. Further clicks fire. Settings apply on restart."
	puzzle.grab_focus.call_deferred()
