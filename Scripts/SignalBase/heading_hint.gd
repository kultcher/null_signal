# heading_hint.gd
# Shows where a mobile signal is going next: a marker on its current
# destination (next patrol point, or an alert destination), a faint line along
# the path it will take to get there, and a chevron on the signal pointing
# along its current leg. Patrols move lane-first, then along the cell, so the
# line shows the turn: the player can see when it will turn and which way.
# Not the whole patrol route: just the current leg.
# Dimmed while the signal dwells at a point (it's about to set off that way);
# hidden when it has nowhere to go, is disabled, or is an unrevealed guard.

class_name HeadingHint extends Node2D

const ORBIT_RADIUS := 34.0
const SIZE := 11.0
const MOVING_COLOR := Color(1.0, 0.82, 0.25, 0.95)
const WAITING_COLOR := Color(1.0, 0.82, 0.25, 0.4)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.7)
const PATH_ALPHA := 0.45
const PATH_WIDTH := 2.0
const DASH_PX := 8.0
const GAP_PX := 7.0
const MARKER_RADIUS := 9.0

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
	var target: Vector2 = destination["position"]
	var here: Vector2 = tm.cell_lane_to_screen(sig.runtime_cell_x, sig.runtime_lane_pos)
	# Path in local coordinates: lane leg first (if any), then the cell leg.
	var corner: Vector2 = tm.cell_lane_to_screen(sig.runtime_cell_x, target.y) - here
	var end: Vector2 = tm.cell_lane_to_screen(target.x, target.y) - here
	var points := PackedVector2Array([Vector2.ZERO])
	if corner.length() > 1.0 and corner.distance_to(end) > 1.0:
		points.append(corner)
	points.append(end)
	if end.length() < 2.0:
		return

	var color: Color = WAITING_COLOR if destination["waiting"] else MOVING_COLOR

	# Path: start outside the icon so the line doesn't cover it.
	_draw_dashed(points, ORBIT_RADIUS, Color(color, color.a * PATH_ALPHA))

	# Destination marker: ring with four ticks.
	draw_arc(end, MARKER_RADIUS, 0.0, TAU, 20, OUTLINE_COLOR, 3.5, true)
	draw_arc(end, MARKER_RADIUS, 0.0, TAU, 20, color, 1.8, true)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(end + d * (MARKER_RADIUS - 3.0), end + d * (MARKER_RADIUS + 4.0), color, 1.8)

	# Chevron along the current leg (the way it's actually moving now).
	var dir := (points[1] - points[0]).normalized()
	var tip := dir * (ORBIT_RADIUS + SIZE)
	var base := dir * ORBIT_RADIUS
	var side := dir.orthogonal() * SIZE * 0.8
	var chevron := PackedVector2Array([tip, base + side, base - side])
	draw_colored_polygon(chevron, color)
	chevron.append(tip)
	draw_polyline(chevron, OUTLINE_COLOR, 1.5, true)

# Dashed polyline on a fixed dash grid, skipping the first `skip` pixels.
func _draw_dashed(points: PackedVector2Array, skip: float, color: Color) -> void:
	var walked := 0.0
	var period := DASH_PX + GAP_PX
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var seg_len := a.distance_to(b)
		if seg_len <= 0.0:
			continue
		var dir := (b - a) / seg_len
		var d := walked - fposmod(walked, period)
		while d < walked + seg_len:
			var d0 := maxf(maxf(d, walked), skip)
			var d1 := minf(d + DASH_PX, walked + seg_len)
			if d1 > d0:
				draw_line(a + dir * (d0 - walked), a + dir * (d1 - walked), color, PATH_WIDTH)
			d += period
		walked += seg_len
