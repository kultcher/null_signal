class_name MobilityController extends Node

enum State { PATROL, RESPONDING_ALERT, INVESTIGATING, RETURNING_TO_PATROL }

var active_sig: ActiveSignal
var _mobility: MobilityComponent
var _timeline_manager: Node2D
var _signal_manager: Node2D

var _state: State = State.PATROL
var _patrol_index: int = 0
var _patrol_direction: int = 1
var _return_patrol_index: int = -1
var _dwell_timer: float = 0.0
var _investigate_timer: float = 0.0
var _alert_response_time_remaining: float = 0.0
var _current_alert: GuardAlertData = null
var _alert_destination_cell_x: float = 0.0
var _alert_destination_lane_pos: float = 0.0
var _last_move_dir: Vector2 = Vector2.ZERO
const ALERT_HORIZONTAL_OFFSET := 28.0
const ALERT_VERTICAL_OFFSET := 18.0

func initialize(target_active_sig: ActiveSignal) -> void:
	active_sig = target_active_sig
	_mobility = active_sig.data.mobility
	_timeline_manager = CommandDispatch.timeline_manager
	_signal_manager = CommandDispatch.signal_manager

	if _mobility == null or not _mobility.enabled:
		set_process(false)
		return

	if _mobility.patrol_points.is_empty():
		var fallback_point: MobilityPatrolPoint = MobilityPatrolPoint.new()
		fallback_point.cell_x = active_sig.start_cell_index
		fallback_point.lane = active_sig.data.lane
		_mobility.patrol_points.append(fallback_point)

	active_sig.runtime_cell_x = active_sig.start_cell_index
	active_sig.runtime_lane = active_sig.data.lane
	active_sig.runtime_lane_pos = float(active_sig.data.lane)
	active_sig.runtime_body_facing_deg = active_sig.data.facing_deg
	active_sig.runtime_position_initialized = true

	GlobalEvents.guard_alert_raised.connect(_on_guard_alert_raised)
	set_process(true)

func _exit_tree() -> void:
	if GlobalEvents.guard_alert_raised.is_connected(_on_guard_alert_raised):
		GlobalEvents.guard_alert_raised.disconnect(_on_guard_alert_raised)

func _process(delta: float) -> void:
	if _mobility == null or _mobility.patrol_points.is_empty():
		return
	if active_sig == null or active_sig.is_disabled:
		return
	if _mobility.movement_disabled:
		return

	_prune_expired_alert(delta)
	_update_render_offset()
	_update_reveal_state()

	match _state:
		State.PATROL:
			_process_patrol(delta)
		State.RESPONDING_ALERT:
			_process_alert_move(delta)
		State.INVESTIGATING:
			_process_investigate(delta)
		State.RETURNING_TO_PATROL:
			_process_return(delta)

func _process_patrol(delta: float) -> void:
	if _dwell_timer > 0.0:
		_dwell_timer -= delta
		return

	var target: MobilityPatrolPoint = _mobility.patrol_points[_patrol_index]
	var arrived := _move_toward(target.cell_x, target.lane, delta)
	if not arrived:
		return

	_dwell_timer = maxf(0.0, target.dwell_sec)
	_patrol_index = _next_patrol_index()

func _process_alert_move(delta: float) -> void:
	if _current_alert == null:
		_begin_return_to_patrol()
		return

	var arrived := _move_toward(_alert_destination_cell_x, _alert_destination_lane_pos, delta)
	if not arrived:
		return

	_investigate_timer = _mobility.investigate_duration_sec
	if _current_alert.investigate_sec_override >= 0.0:
		_investigate_timer = _current_alert.investigate_sec_override
	_investigate_timer = maxf(_investigate_timer, 0.1)
	_state = State.INVESTIGATING

func _process_investigate(delta: float) -> void:
	GlobalEvents.mobile_investigating.emit(active_sig)
	_investigate_timer -= delta
	if _investigate_timer > 0.0:
		return

	_current_alert = null
	_alert_response_time_remaining = 0.0
	_begin_return_to_patrol()

func _process_return(delta: float) -> void:
	if _return_patrol_index < 0:
		_return_patrol_index = _find_nearest_patrol_index()

	var target: MobilityPatrolPoint = _mobility.patrol_points[_return_patrol_index]
	var arrived := _move_toward(target.cell_x, target.lane, delta)
	if not arrived:
		return

	_patrol_index = _return_patrol_index
	_return_patrol_index = -1
	_state = State.PATROL

func _move_toward(target_cell_x: float, target_lane_pos: float, delta: float) -> bool:
	var cell_w: float = 1.0
	var lane_h: float = 1.0
	if _timeline_manager != null:
		cell_w = maxf(1.0, _timeline_manager.cell_width_px)
		lane_h = maxf(1.0, _timeline_manager.lane_height)

	var speed_visual: float = _get_move_speed_cells_per_sec() * cell_w * delta
	var lane_target := target_lane_pos
	var lane_delta := lane_target - active_sig.runtime_lane_pos

	if absf(lane_delta) > 0.001:
		var lane_step := speed_visual / lane_h
		var lane_dir := signf(lane_delta)
		if absf(lane_delta) <= lane_step:
			active_sig.runtime_lane_pos = lane_target
			active_sig.runtime_lane = int(round(lane_target))
		else:
			active_sig.runtime_lane_pos += lane_dir * lane_step
			active_sig.runtime_lane = int(round(active_sig.runtime_lane_pos))
		_last_move_dir = Vector2(0.0, lane_dir)
		_update_facing(Vector2(0.0, lane_dir))
		return false

	var cell_delta := target_cell_x - active_sig.runtime_cell_x
	if absf(cell_delta) > 0.001:
		var cell_step := speed_visual / cell_w
		var cell_dir := signf(cell_delta)
		if absf(cell_delta) <= cell_step:
			active_sig.runtime_cell_x = target_cell_x
		else:
			active_sig.runtime_cell_x += cell_dir * cell_step
		_last_move_dir = Vector2(cell_dir, 0.0)
		_update_facing(Vector2(cell_dir, 0.0))
		active_sig.runtime_lane_pos = lane_target
		active_sig.runtime_lane = int(round(lane_target))
		return false

	active_sig.runtime_cell_x = target_cell_x
	active_sig.runtime_lane_pos = lane_target
	active_sig.runtime_lane = int(round(lane_target))
	return true

# Where the signal is currently headed, in (cell, lane), for the on-map
# heading hint. Returns {} when it has nowhere to go (stationary, disabled).
# "waiting" is true while dwelling at a patrol point; the destination is then
# the next point it will walk to.
func get_current_destination() -> Dictionary:
	if _mobility == null or _mobility.patrol_points.is_empty() or active_sig == null:
		return {}
	if active_sig.is_disabled or _mobility.movement_disabled:
		return {}
	var target := Vector2.ZERO
	var waiting := false
	match _state:
		State.PATROL:
			var point: MobilityPatrolPoint = _mobility.patrol_points[_patrol_index]
			target = Vector2(point.cell_x, point.lane)
			waiting = _dwell_timer > 0.0
		State.RESPONDING_ALERT:
			target = Vector2(_alert_destination_cell_x, _alert_destination_lane_pos)
		State.INVESTIGATING:
			return {}
		State.RETURNING_TO_PATROL:
			var index := _return_patrol_index if _return_patrol_index >= 0 else _find_nearest_patrol_index()
			var point: MobilityPatrolPoint = _mobility.patrol_points[index]
			target = Vector2(point.cell_x, point.lane)
	var here := Vector2(active_sig.runtime_cell_x, active_sig.runtime_lane_pos)
	if here.distance_to(target) < 0.01:
		return {}
	return {"position": target, "waiting": waiting}

func _update_facing(dir: Vector2) -> void:
	if dir.length_squared() <= 0.0001:
		return
	# Convert timeline units to screen-proportional vector so facing
	# matches actual rendered movement direction.
	var visual_dir := dir
	if _timeline_manager != null:
		visual_dir = Vector2(
			dir.x * _timeline_manager.cell_width_px,
			dir.y * _timeline_manager.lane_height
		)
	active_sig.runtime_body_facing_deg = rad_to_deg(atan2(visual_dir.y, visual_dir.x))

func _next_patrol_index() -> int:
	var max_i := _mobility.patrol_points.size() - 1
	if max_i <= 0:
		return 0

	if _mobility.patrol_mode == MobilityComponent.PatrolMode.LOOP:
		return (_patrol_index + 1) % _mobility.patrol_points.size()

	var candidate := _patrol_index + _patrol_direction
	if candidate < 0 or candidate > max_i:
		_patrol_direction *= -1
		candidate = _patrol_index + _patrol_direction
	return clampi(candidate, 0, max_i)

func _find_nearest_patrol_index() -> int:
	var nearest: int = 0
	var best_dist: float = INF
	var pos: Vector2 = Vector2(active_sig.runtime_cell_x, active_sig.runtime_lane_pos)
	for i in range(_mobility.patrol_points.size()):
		var point: MobilityPatrolPoint = _mobility.patrol_points[i]
		var dist: float = pos.distance_to(Vector2(point.cell_x, point.lane))
		if dist < best_dist:
			best_dist = dist
			nearest = i
	return nearest

func _on_guard_alert_raised(alert: GuardAlertData) -> void:
	if alert == null:
		return
	if _mobility == null:
		return
	if alert.target_instance_id != 0 and active_sig.get_instance_id() != alert.target_instance_id:
		return
	if alert.target_signal_id != "" and active_sig.data.system_id != alert.target_signal_id:
		return
	if _current_alert != null:
		return
	if alert.ttl_sec <= 0.0:
		alert.ttl_sec = _mobility.default_alert_ttl_sec

	_current_alert = alert.duplicate(true)
	_alert_response_time_remaining = _current_alert.ttl_sec
	_set_alert_destination()
	_state = State.RESPONDING_ALERT
	_dwell_timer = 0.0

func _prune_expired_alert(delta: float) -> void:
	if _state != State.RESPONDING_ALERT:
		return
	if _current_alert == null:
		return
	_alert_response_time_remaining = maxf(0.0, _alert_response_time_remaining - delta)
	if _alert_response_time_remaining <= 0.0:
		_current_alert = null
		_alert_response_time_remaining = 0.0
		_begin_return_to_patrol()

func _begin_return_to_patrol() -> void:
	_alert_destination_cell_x = active_sig.runtime_cell_x
	_alert_destination_lane_pos = active_sig.runtime_lane_pos
	_return_patrol_index = _find_nearest_patrol_index()
	_state = State.RETURNING_TO_PATROL

func _get_move_speed_cells_per_sec() -> float:
	if _mobility == null:
		return 0.0
	if _state == State.RESPONDING_ALERT:
		return _mobility.move_speed_cells_per_sec * maxf(1.0, _mobility.alert_move_speed_multiplier)
	return _mobility.move_speed_cells_per_sec

func _update_render_offset() -> void:
	if active_sig == null:
		return
	active_sig.runtime_render_offset = Vector2.ZERO

func has_movement_facing() -> bool:
	return _last_move_dir.length_squared() > 0.0001

func get_movement_facing_deg() -> float:
	return active_sig.runtime_body_facing_deg

func has_alert_focus() -> bool:
	return _current_alert != null and (_state == State.RESPONDING_ALERT or _state == State.INVESTIGATING)

func get_alert_focus_deg() -> float:
	if not has_alert_focus():
		return active_sig.runtime_detection_facing_deg

	var dir := Vector2(
		_current_alert.target_cell_x - active_sig.runtime_cell_x,
		float(_current_alert.target_lane) - active_sig.runtime_lane_pos
	)
	if dir.length_squared() <= 0.0001:
		return active_sig.runtime_detection_facing_deg

	var visual_dir := dir
	if _timeline_manager != null:
		visual_dir = Vector2(
			dir.x * _timeline_manager.cell_width_px,
			dir.y * _timeline_manager.lane_height
		)
	return wrapf(rad_to_deg(atan2(visual_dir.y, visual_dir.x)) + 180.0, -180.0, 180.0)

func is_in_alert_state() -> bool:
	return _state == State.RESPONDING_ALERT or _state == State.INVESTIGATING

func _set_alert_destination() -> void:
	if _current_alert == null:
		_alert_destination_cell_x = active_sig.runtime_cell_x
		_alert_destination_lane_pos = active_sig.runtime_lane_pos
		return

	var cell_w: float = 96.0
	var lane_h: float = 48.0
	if _timeline_manager != null:
		cell_w = maxf(1.0, _timeline_manager.cell_width_px)
		lane_h = maxf(1.0, _timeline_manager.lane_height)

	var horizontal_offset_cells := ALERT_HORIZONTAL_OFFSET / cell_w
	var vertical_offset_lanes := ALERT_VERTICAL_OFFSET / lane_h

	var cell_delta := _current_alert.target_cell_x - active_sig.runtime_cell_x
	var lane_delta := float(_current_alert.target_lane) - active_sig.runtime_lane_pos

	_alert_destination_cell_x = _current_alert.target_cell_x
	_alert_destination_lane_pos = float(_current_alert.target_lane)

	if absf(cell_delta) > 0.001:
		_alert_destination_cell_x -= signf(cell_delta) * horizontal_offset_cells
		return
	if absf(lane_delta) > 0.001:
		_alert_destination_lane_pos -= signf(lane_delta) * vertical_offset_lanes

func _update_reveal_state() -> void:
	if active_sig.instance_node == null:
		return
	var reveal := _is_revealed_to_player()
	active_sig.instance_node.set_guard_revealed(reveal)

func _is_revealed_to_player() -> bool:
	if _timeline_manager == null:
		return true
	if _signal_manager == null:
		return true

	var runner_cell: float = _timeline_manager.current_cell_pos
	var guard_cell: float = active_sig.runtime_cell_x
	var runner_dist: float = absf(guard_cell - runner_cell)
	if _signal_manager != null:
		runner_dist = _signal_manager.get_horizontal_runner_distance_cells(active_sig)
	if runner_dist <= _mobility.reveal_range_from_runner_cells:
		return true

	for other_sig in _signal_manager.signal_queue:
		if other_sig == active_sig:
			continue
		if other_sig.data.type != SignalData.Type.CAMERA:
			continue
		if other_sig.is_disabled:
			continue
		if not _camera_has_active_session(other_sig):
			continue
		if _camera_is_puzzle_locked(other_sig):
			continue

		var cam_cell: float = other_sig.start_cell_index
		if other_sig.runtime_position_initialized:
			cam_cell = other_sig.runtime_cell_x
		var dist: float = absf(cam_cell - guard_cell)
		if dist <= _mobility.reveal_range_from_camera_cells:
			return true

	return false

func _camera_has_active_session(camera_sig: ActiveSignal) -> bool:
	if camera_sig == null:
		return false
	if camera_sig.terminal_session == null:
		return false
	return camera_sig.terminal_session.has_tab

func _camera_is_puzzle_locked(camera_sig: ActiveSignal) -> bool:
	if camera_sig == null or camera_sig.data == null:
		return false
	if camera_sig.data.puzzle == null:
		return false
	return camera_sig.data.puzzle.is_locked()
