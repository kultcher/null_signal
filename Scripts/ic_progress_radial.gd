class_name ICProgressRadial extends TextureProgressBar

# Used when a module doesn't pick a gradient. The scene's own texture is an
# empty GradientTexture2D, which Godot draws as its magenta "missing texture"
# checkerboard.
const DEFAULT_GRADIENT_PATH := "res://Visuals/Gradients/cyan_gradient_tex.tres"
# Each extra timed IC on the same signal draws its ring this much smaller, so
# rings nest instead of overlapping.
const RING_SCALE_STEP := 0.78

var active: bool = false
var show_when_idle: bool = false
var new_max: float = 0.0
var _countdown_timer: Timer = null

func _ready() -> void:
	var gradient_texture := texture_progress as GradientTexture2D
	if texture_progress == null or (gradient_texture != null and gradient_texture.gradient == null):
		set_gradient(DEFAULT_GRADIENT_PATH)
	resized.connect(_center_pivot)
	_center_pivot()

func _center_pivot() -> void:
	pivot_offset = size * 0.5

# 0 = outermost ring; higher indices draw smaller, inside the earlier rings.
func set_ring_index(index: int) -> void:
	scale = Vector2.ONE * pow(RING_SCALE_STEP, maxi(0, index))

func _process(_delta: float) -> void:
	if not active:
		return
	if _countdown_timer == null or not is_instance_valid(_countdown_timer):
		stop()
		return
	value = clampf(_countdown_timer.time_left, 0.0, max_value)

func start(duration: float = -1.0, countdown_timer: Timer = null) -> void:
	if duration >= 0.0:
		new_max = duration
		max_value = duration
	_countdown_timer = countdown_timer
	reset()
	visible = true
	active = true

func stop() -> void:
	active = false
	_countdown_timer = null
	reset()
	visible = show_when_idle

func reset() -> void:
	value = new_max

func configure(_active_sig: ActiveSignal, progress: float) -> void:
	new_max = progress
	max_value = new_max
	reset()

func set_idle_visible(value: bool) -> void:
	show_when_idle = value
	if not active:
		visible = show_when_idle

func set_gradient(path: String):
	var grad = load(path)
	texture_progress = grad
