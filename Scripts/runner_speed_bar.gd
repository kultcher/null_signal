# runner_speed_bar.gd
# Thin bar under the runner showing how long a timed slow/hustle has left
# (TimelineManager.speed_time_left / speed_toggle_sec). Hidden while walking;
# blinks in the last few seconds so the change back doesn't surprise.
class_name RunnerSpeedBar extends Node2D

const WIDTH := 138.0          # runner panel width (RunnerTeam local units)
const HEIGHT := 12.0
const GAP := 10.0             # below the panel's bottom edge (y = 69)
const PANEL_HALF := 69.0
const WARN_SEC := 3.0
const HUSTLE_COLOR := Color(1.0, 0.75, 0.25)
const SLOW_COLOR := Color(0.35, 0.7, 1.0)
const TRACK_COLOR := Color(0.0, 0.0, 0.0, 0.6)

var timeline_manager: Node
var _was_active := false

func setup(timeline: Node) -> void:
	timeline_manager = timeline

func _process(_delta: float) -> void:
	if timeline_manager == null:
		return
	var active: bool = timeline_manager.speed_mode != &"walk"
	if active or _was_active:
		queue_redraw()
	_was_active = active

func _draw() -> void:
	if timeline_manager == null or timeline_manager.speed_mode == &"walk":
		return
	var total: float = maxf(0.001, timeline_manager.speed_toggle_sec)
	var ratio := clampf(timeline_manager.speed_time_left / total, 0.0, 1.0)
	var color := HUSTLE_COLOR if timeline_manager.speed_mode == &"hustle" else SLOW_COLOR
	if timeline_manager.speed_time_left < WARN_SEC and int(Time.get_ticks_msec() / 200) % 2 == 0:
		color.a = 0.35
	var rect := Rect2(-WIDTH * 0.5, PANEL_HALF + GAP, WIDTH, HEIGHT)
	draw_rect(rect.grow(2.0), TRACK_COLOR, true)
	draw_rect(Rect2(rect.position, Vector2(WIDTH * ratio, HEIGHT)), color, true)
