class_name EscalationSpawnBehavior extends Resource

const COMBAT_DRONE_PREFAB := preload("res://Resources/SignalPrefabs/combat_drone.tres")

@export var enabled: bool = true
@export var initial_spawn_delay_sec: float = 10.0
@export var repeat_spawn_delay_sec: float = 30.0
@export_multiline var debug_description: String = ""

var _spawn_loop_token: int = 0
var _spawn_count: int = 0

func on_started(active_sig: ActiveSignal, component: EscalationComponent) -> void:
	if active_sig == null or component == null:
		return
	_spawn_loop_token += 1
	_run_spawn_loop(active_sig, component, _spawn_loop_token)

func on_stopped(_active_sig: ActiveSignal, _component: EscalationComponent) -> void:
	_spawn_loop_token += 1

func _run_spawn_loop(active_sig: ActiveSignal, component: EscalationComponent, token: int) -> void:
	if not await _wait_for_delay(initial_spawn_delay_sec, token):
		return

	while _can_continue_spawning(active_sig, component, token):
		_spawn_drone_toward_runner(active_sig, component)
		if not await _wait_for_delay(repeat_spawn_delay_sec, token):
			return

func _can_continue_spawning(active_sig: ActiveSignal, component: EscalationComponent, token: int) -> bool:
	if token != _spawn_loop_token:
		return false
	if active_sig == null or active_sig.is_disabled:
		return false
	if component == null or not component.is_active():
		return false
	if CommandDispatch.signal_manager == null or CommandDispatch.timeline_manager == null:
		return false
	return true

func _wait_for_delay(delay_sec: float, token: int) -> bool:
	if token != _spawn_loop_token:
		return false
	if delay_sec <= 0.0:
		return true
	if GlobalEvents == null or GlobalEvents.get_tree() == null:
		return false
	await GlobalEvents.get_tree().create_timer(delay_sec).timeout
	return token == _spawn_loop_token

func _spawn_drone_toward_runner(active_sig: ActiveSignal, _component: EscalationComponent) -> void:
	var signal_manager = CommandDispatch.signal_manager
	var timeline_manager = CommandDispatch.timeline_manager
	if signal_manager == null or timeline_manager == null:
		return

	var spawned_data := COMBAT_DRONE_PREFAB.duplicate(true) as SignalData
	if spawned_data == null:
		return

	_spawn_count += 1
	var spawn_lane := 2
	var spawn_cell = timeline_manager.current_cell_pos + 8.0
	if timeline_manager.map_mode:
		# Stay on the current feed; anything past the section end would be hidden.
		spawn_cell = minf(spawn_cell, timeline_manager.get_current_section().end_cell - 0.5)
	var target_cell = timeline_manager.current_cell_pos
	var facing_deg := 0.0 if target_cell <= spawn_cell else 180.0

	spawned_data.lane = spawn_lane
	spawned_data.facing_deg = facing_deg
	spawned_data.system_id = "%s_add_%02d" % [active_sig.data.system_id, _spawn_count]
	spawned_data.display_name = "ADD-" + str(_spawn_count).pad_zeros(2)

	if spawned_data.mobility != null:
		var patrol_point := MobilityPatrolPoint.new()
		patrol_point.cell_x = target_cell
		patrol_point.lane = spawn_lane
		patrol_point.dwell_sec = 0.0
		patrol_point.facing_deg = facing_deg
		spawned_data.mobility.patrol_points = [patrol_point]
		spawned_data.mobility.patrol_mode = MobilityComponent.PatrolMode.LOOP

	if spawned_data.detection != null:
		spawned_data.detection.reset_runtime_state()
		spawned_data.detection.follow_movement_facing = true
		if not spawned_data.detection.patrol_points.is_empty():
			for patrol_point in spawned_data.detection.patrol_points:
				if patrol_point == null:
					continue
				patrol_point.facing_deg = facing_deg

	signal_manager.spawn_signal_data(spawned_data, spawn_cell)
