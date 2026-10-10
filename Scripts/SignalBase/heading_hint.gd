# heading_hint.gd
# Small chevron orbiting a mobile signal, pointing at where it's currently
# headed (its next patrol point, or an alert destination). Not the whole
# patrol route: just enough that the player can read intent at a glance,
# since they can't otherwise steer the runner around it.
# Dimmed while the signal dwells at a point (it's about to set off that way);
# hidden when it has nowhere to go, is disabled, or is an unrevealed guard.

class_name HeadingHint extends Node2D

const ORBIT_RADIUS := 34.0
const SIZE := 11.0
const MOVING_COLOR := Color(1.0, 0.82, 0.25, 0.95)
const WAITING_COLOR := Color(1.0, 0.82, 0.25, 0.4)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.7)

var _entity: Node2D
var _mobility: MobilityController

func setup(entity: Node2D, mobility: MobilityController) -> void:
	_entity = entity
	_mobility = mobility
	z_index = 5

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if _entity == null or _mobility == null or not is_instance_valid(_mobility):
		return
	# Unrevealed guards hide their shape; the hint must not give them away.
	var shape = _entity.get("shape")
	if shape != null and not shape.visible:
		return
	var tm = CommandDispatch.timeline_manager
	if tm == null:
		return
	var destination := _mobility.get_current_destination()
	if destination.is_empty():
		return
	var sig: ActiveSignal = _mobility.active_sig
	var here: Vector2 = tm.cell_lane_to_screen(sig.runtime_cell_x, sig.runtime_lane_pos)
	var target_pos: Vector2 = destination["position"]
	var there: Vector2 = tm.cell_lane_to_screen(target_pos.x, target_pos.y)
	var dir := there - here
	if dir.length() < 2.0:
		return
	dir = dir.normalized()
	var color := WAITING_COLOR if destination["waiting"] else MOVING_COLOR
	var tip := dir * (ORBIT_RADIUS + SIZE)
	var base := dir * ORBIT_RADIUS
	var side := dir.orthogonal() * SIZE * 0.8
	var chevron := PackedVector2Array([tip, base + side, base - side])
	draw_colored_polygon(chevron, color)
	chevron.append(tip)
	draw_polyline(chevron, OUTLINE_COLOR, 1.5, true)
