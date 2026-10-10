# deck_cable.gd
# Draws patch cables between metadata points on DeviceShells (e.g. an aux module's
# cable_port to the deck's exp_port_a). Cables lie on the desk between the deck and the
# aux devices, and follow devices while they are dragged.

class_name DeckCable
extends Node2D

@export var cable_color := Color(0.045, 0.045, 0.045)
@export var highlight_color := Color(0.32, 0.33, 0.30, 0.55)
@export var width := 11.0

var links: Array[Dictionary] = []


## a_dir / b_dir: the direction the cable leaves each port (screen space, unit vector).
func add_link(a: DeviceShell, a_key: String, a_dir: Vector2, b: DeviceShell, b_key: String, b_dir: Vector2, slack := 70.0) -> void:
	links.append({"a": a, "a_key": a_key, "a_dir": a_dir, "b": b, "b_key": b_key, "b_dir": b_dir, "slack": slack})


func remove_links_for(shell: DeviceShell) -> void:
	links.assign(links.filter(func(l): return l.a != shell and l.b != shell))
	queue_redraw()


func _process(_delta: float) -> void:
	if not links.is_empty():
		queue_redraw()


func _draw() -> void:
	for l in links:
		if not (is_instance_valid(l.a) and is_instance_valid(l.b)):
			continue
		var p0: Vector2 = to_local(l.a.get_point_global(l.a_key))
		var p1: Vector2 = to_local(l.b.get_point_global(l.b_key))
		var reach: float = l.slack + p0.distance_to(p1) * 0.35
		var c0: Vector2 = p0 + (l.a_dir as Vector2).rotated(l.a.rotation) * reach
		var c1: Vector2 = p1 + (l.b_dir as Vector2).rotated(l.b.rotation) * reach
		var pts := PackedVector2Array()
		var n := 36
		for i in n + 1:
			var t := float(i) / n
			var u := 1.0 - t
			pts.append(p0 * u * u * u + c0 * 3.0 * u * u * t + c1 * 3.0 * u * t * t + p1 * t * t * t)

		var shadow := PackedVector2Array()
		var hl := PackedVector2Array()
		for p in pts:
			shadow.append(p + Vector2(5, 8))
			hl.append(p + Vector2(-1.5, -2.5))
		draw_polyline(shadow, Color(0, 0, 0, 0.35), width + 4.0, true)
		draw_polyline(pts, cable_color, width, true)
		draw_polyline(hl, highlight_color, 2.0, true)
		_draw_plug(p0, (pts[2] - pts[0]).normalized())
		_draw_plug(p1, (pts[n - 2] - pts[n]).normalized())


func _draw_plug(p: Vector2, dir: Vector2) -> void:
	var side := Vector2(-dir.y, dir.x)
	var boot := PackedVector2Array([
		p + side * 9.0, p + side * 9.0 + dir * 24.0,
		p - side * 9.0 + dir * 24.0, p - side * 9.0,
	])
	draw_colored_polygon(boot, Color(0.08, 0.08, 0.08))
	draw_polyline(PackedVector2Array([boot[0], boot[1]]), highlight_color, 1.5, true)
