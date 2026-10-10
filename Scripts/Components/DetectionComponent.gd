# DetectionComponent.gd
# Signal component for vision behaviors

class_name DetectionComponent extends Resource

enum ShapeType { CONE, ARC, CIRCLE }
enum ThreatState { DETECT, ATTACK }

@export var watch_offset_cells: float = -1.0:
	set = _set_watch_offset_cells
@export var vision_length_cells: float = 2.0:
	set = _set_vision_length_cells
@export var vision_angle_deg: float = 30.0:
	set = _set_vision_angle_deg
@export var vision_segments: int = 12:
	set = _set_vision_segments
@export var shape_type: ShapeType = ShapeType.CONE:
	set = _set_shape_type
@export var delay: float = 0.0
@export var follow_movement_facing: bool = true:
	set = _set_follow_movement_facing
@export var turn_speed_deg_per_sec: float = 120.0:
	set = _set_turn_speed_deg_per_sec
@export var patrol_points: Array[DetectionPatrolPoint] = []:
	set = _set_patrol_points
@export var threat_state: ThreatState = ThreatState.DETECT:
	set = _set_threat_state

var detection_disabled: bool = false
var _patrol_index: int = 0
var _patrol_direction: int = 1
var _dwell_timer: float = 0.0

func _set_vision_length_cells(value: float) -> void:
	vision_length_cells = max(0.0, value)
	emit_changed()

func _set_watch_offset_cells(value: float) -> void:
	watch_offset_cells = value
	emit_changed()

func _set_vision_angle_deg(value: float) -> void:
	vision_angle_deg = clamp(value, 1.0, 179.0)
	emit_changed()

func _set_vision_segments(value: int) -> void:
	vision_segments = max(3, value)
	emit_changed()

func _set_shape_type(value: ShapeType) -> void:
	shape_type = value
	emit_changed()

func _set_follow_movement_facing(value: bool) -> void:
	follow_movement_facing = value
	emit_changed()

func _set_turn_speed_deg_per_sec(value: float) -> void:
	turn_speed_deg_per_sec = maxf(0.0, value)
	emit_changed()

func _set_patrol_points(value: Array[DetectionPatrolPoint]) -> void:
	patrol_points = value
	reset_runtime_state()
	emit_changed()

func _set_threat_state(value: ThreatState) -> void:
	threat_state = value
	emit_changed()

func apply_detection(active_sig: ActiveSignal, delta: float) -> void:
	if active_sig.is_disabled or detection_disabled:
		return
	_apply_detection(active_sig, delta)

func initialize_runtime(active_sig: ActiveSignal) -> void:
	if active_sig == null:
		return
	reset_runtime_state()
	if patrol_points.is_empty():
		if not active_sig.runtime_position_initialized:
			active_sig.runtime_detection_facing_deg = active_sig.data.facing_deg
		return
	active_sig.runtime_detection_facing_deg = patrol_points[0].facing_deg

func update_runtime(active_sig: ActiveSignal, delta: float, movement_facing_deg: float, movement_has_facing: bool) -> void:
	if active_sig == null:
		return
	if active_sig.runtime_detection_paused:
		return
	if patrol_points.is_empty():
		if follow_movement_facing and movement_has_facing:
			active_sig.runtime_detection_facing_deg = movement_facing_deg
		return

	if _dwell_timer > 0.0:
		_dwell_timer -= delta
		if _dwell_timer > 0.0:
			return

	var target_point := patrol_points[_patrol_index]
	if not _rotate_toward(active_sig, target_point.facing_deg, delta):
		return

	_dwell_timer = maxf(0.0, target_point.dwell_sec)
	_patrol_index = _next_patrol_index()

func reset_runtime_state() -> void:
	_patrol_index = 0
	_patrol_direction = 1
	_dwell_timer = 0.0

func has_patrol_points() -> bool:
	return not patrol_points.is_empty()

func is_attack_state() -> bool:
	return threat_state == ThreatState.ATTACK

func _rotate_toward(active_sig: ActiveSignal, target_facing_deg: float, delta: float) -> bool:
	var current := wrapf(active_sig.runtime_detection_facing_deg, -180.0, 180.0)
	var target := wrapf(target_facing_deg, -180.0, 180.0)
	var delta_deg := wrapf(target - current, -180.0, 180.0)
	if absf(delta_deg) <= 0.5:
		active_sig.runtime_detection_facing_deg = target
		return true

	var turn_step := turn_speed_deg_per_sec * delta
	if turn_step <= 0.0 or absf(delta_deg) <= turn_step:
		active_sig.runtime_detection_facing_deg = target
		return true

	active_sig.runtime_detection_facing_deg = wrapf(current + signf(delta_deg) * turn_step, -180.0, 180.0)
	return false

func _next_patrol_index() -> int:
	var max_i := patrol_points.size() - 1
	if max_i <= 0:
		return 0
	var candidate := _patrol_index + _patrol_direction
	if candidate < 0 or candidate > max_i:
		_patrol_direction *= -1
		candidate = _patrol_index + _patrol_direction
	return clampi(candidate, 0, max_i)

func build_collision_shape(cell_width_px: float) -> Shape2D:

	match shape_type:
		ShapeType.CIRCLE:
			var circle = CircleShape2D.new()
			circle.radius = max(1.0, vision_length_cells * cell_width_px)
			return circle
		ShapeType.CONE:
			var poly = ConvexPolygonShape2D.new()
			poly.points = _build_polygon_points(cell_width_px)
			return poly
		ShapeType.ARC:
			var poly = ConvexPolygonShape2D.new()
			poly.points = _build_polygon_points(cell_width_px)
			return poly
	return

func get_visual_polygon(cell_width_px: float) -> PackedVector2Array:
	return _build_polygon_points(cell_width_px)

func _build_polygon_points(cell_width_px: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var offset_px = watch_offset_cells * cell_width_px
	var length_px = max(1.0, vision_length_cells * cell_width_px)


	match shape_type:
		ShapeType.CONE:
			var half_width = tan(deg_to_rad(vision_angle_deg * 0.5)) * length_px
			points.append(Vector2(offset_px, 0)) # tip
			points.append(Vector2(offset_px - length_px, -half_width))
			points.append(Vector2(offset_px - length_px, half_width))
		ShapeType.ARC:
			# D-shape profile:
			# - Flat "peripheral" backline cuts through icon center
			# - Rounded front projects outward
			# Depth equals full backline height.
			var depth = length_px
			var half_height = depth * 0.5
			var front_radius = half_height
			var front_center = Vector2(offset_px + depth - front_radius, 0.0)

			points.append(Vector2(offset_px, -half_height))
			points.append(Vector2(front_center.x, -half_height))
			for i in range(vision_segments + 1):
				var t = float(i) / float(vision_segments)
				var theta = lerp(-PI * 0.5, PI * 0.5, t)
				points.append(front_center + Vector2(cos(theta), sin(theta)) * front_radius)
			points.append(Vector2(offset_px, half_height))
		ShapeType.CIRCLE:
			var radius = length_px
			for i in range(vision_segments):
				var t = float(i) / float(vision_segments)
				var theta = lerp(0.0, TAU, t)
				points.append(Vector2(offset_px, 0) + Vector2(cos(theta), sin(theta)) * radius)

	return points

func _apply_detection(active_sig: ActiveSignal, delta):
	GlobalEvents.runner_detected.emit(active_sig)
	active_sig.instance_node.detection_controller.runner_spotted()
	if active_sig.data.response:
		active_sig.data.response.on_detection(active_sig, delta, delay)

func disable_detection():
	detection_disabled = true

func enable_detection():
	detection_disabled = false

func get_desc():
	return "Static"
