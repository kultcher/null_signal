extends Control

@onready var puzzle: FuzzPuzzle = get_parent().get_parent()

func _gui_input(event: InputEvent) -> void:
	puzzle.arena_input(event)

func _draw() -> void:
	if puzzle.state.config == null:
		return
	var config := puzzle.state.config
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.42
	var core := radius * 0.36
	var white := config.neutral_color
	var font := get_theme_default_font()
	draw_circle(center, core, Color(0.04, 0.06, 0.075))
	draw_arc(center, core, 0, TAU, 120, white, 3.0, true)
	draw_arc(center, radius, 0, TAU, 120, white * Color(1, 1, 1, 0.45), 1.0, true)
	for i in 36:
		var direction := Vector2.from_angle(i * TAU / 36.0)
		draw_line(center + direction * (radius - 5), center + direction * (radius + 3), white * Color(1, 1, 1, 0.35), 1.0, true)
	for hit in puzzle.impacts:
		var arc := deg_to_rad(config.impact_arc_deg) * 0.5
		draw_arc(center, core, hit["angle"] - arc, hit["angle"] + arc, 16, config.impact_color(hit["points"], hit["age"]), 9.0, true)
	if puzzle.show_sweet_spot:
		var half := deg_to_rad(config.sweet_spot_arc_deg) * 0.5
		draw_arc(center, core + 15, puzzle.state.sweet_spot_angle - half, puzzle.state.sweet_spot_angle + half, 36, Color(0.3, 1, 0.55), 2.0, true)
	for packet in puzzle.state.packets:
		var fraction: float = 1.0 - packet["remaining"] / config.flight_time_sec
		var direction := Vector2.from_angle(packet["angle"])
		var point := center + direction * lerpf(radius - 22, core, fraction)
		draw_line(point + direction * 12, point, white, 2.0, true)
		draw_circle(point, 3.5, white)
	var aim := Vector2.from_angle(puzzle.aim_angle)
	var tangent := aim.orthogonal()
	var cannon := center + aim * (radius - 8)
	var color := white if puzzle.has_puzzle_focus() else white * Color(1, 1, 1, 0.35)
	draw_colored_polygon(PackedVector2Array([cannon + tangent * 9, cannon - tangent * 9, cannon - aim * 23]), color)
	draw_string(font, center + Vector2(-24, 5), "CORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, white)
	var count := mini(config.max_ammo, 20)
	for i in count:
		draw_circle(Vector2(size.x * 0.5 + (i - (count - 1) * 0.5) * 14, size.y - 10), 3.0, white if i < puzzle.state.ammo else Color(0.2, 0.25, 0.28))
