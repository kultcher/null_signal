class_name GlitchRipple extends Node2D

var age := 0.0
const LIFETIME := 0.7

func _process(delta: float) -> void:
	age += delta
	queue_redraw()
	if age >= LIFETIME:
		queue_free()

func _draw() -> void:
	for i in range(3):
		var progress := clampf(age / LIFETIME - float(i) * 0.12, 0.0, 1.0)
		if progress > 0.0:
			draw_arc(Vector2.ZERO, 8.0 + progress * 65.0, 0, TAU, 48, Color(0.25, 0.85, 1.0, (1.0 - progress) * 0.9), 2.0, true)
