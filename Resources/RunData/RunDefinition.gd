class_name RunDefinition extends RefCounted

class SpawnBuilder extends RefCounted:
	var _run: RunDefinition
	var _spawn: Dictionary

	func _init(run_definition: RunDefinition, signal_data: SignalData, cell_index: float) -> void:
		_run = run_definition
		_spawn = {
			"signal_data": signal_data,
			"cell_index": cell_index,
		}

	func id(system_id: String) -> SpawnBuilder:
		_spawn["system_id"] = system_id
		return self

	func display_name(name: String) -> SpawnBuilder:
		_spawn["display_name"] = name
		return self

	func spoof_id(value: String) -> SpawnBuilder:
		_spawn["spoof_id"] = value
		return self

	func lane(value: int) -> SpawnBuilder:
		_spawn["lane"] = value
		return self

	func facing(value: float) -> SpawnBuilder:
		_spawn["facing_deg"] = value
		return self

	func vision(angle_deg: float, length_cells: float, watch_offset_cells: float = INF) -> SpawnBuilder:
		var detection := _get_or_create_detection_override()
		detection.vision_angle_deg = angle_deg
		detection.vision_length_cells = length_cells
		if not is_inf(watch_offset_cells):
			detection.watch_offset_cells = watch_offset_cells
		return self

	func watch_offset(value: float) -> SpawnBuilder:
		var detection := _get_or_create_detection_override()
		detection.watch_offset_cells = value
		return self

	func turn_speed(deg_per_sec: float) -> SpawnBuilder:
		var detection := _get_or_create_detection_override()
		detection.turn_speed_deg_per_sec = deg_per_sec
		return self

	func move_speed(cells_per_sec: float) -> SpawnBuilder:
		var mobility := _get_or_create_mobility_override()
		mobility.move_speed_cells_per_sec = cells_per_sec
		return self

	func detection_sweep(point1: Array[float], point2: Array[float], point3: Array[float] = [], point4: Array[float] = []) -> SpawnBuilder:
		_spawn["detection_patrol_points"] = _run.make_detection_sweep(point1, point2, point3, point4)
		return self

	func patrol(point1: Array[float], point2: Array[float], point3: Array[float] = [], point4: Array[float] = []) -> SpawnBuilder:
		_spawn["patrol_points"] = _run.make_patrol_route(point1, point2, point3, point4)
		return self

	func add_ic(name: StringName, difficulty: int) -> SpawnBuilder:
		return _add_ic_module(_run.build_ic(name, difficulty))

	func add_ic_custom(name: StringName, params: Dictionary) -> SpawnBuilder:
		return _add_ic_module(_run.build_custom_ic(name, params))

	func add_puzzle(name: StringName, difficulty: int) -> SpawnBuilder:
		_spawn["puzzle"] = _run.build_puzzle(name, difficulty)
		return self

	func add_puzzle_custom(name: StringName, params: Dictionary) -> SpawnBuilder:
		_spawn["puzzle"] = _run.build_custom_puzzle(name, params)
		return self

	func build() -> Dictionary:
		return _spawn.duplicate(true)

	func _add_ic_module(module: Resource) -> SpawnBuilder:
		if module == null:
			return self
		var ic := _get_or_create_ic_override()
		ic.add_module(module)
		return self

	func _get_or_create_detection_override() -> DetectionComponent:
		if _spawn.has("detection") and _spawn["detection"] != null:
			return _spawn["detection"]
		var signal_data := _spawn["signal_data"] as SignalData
		var detection: DetectionComponent
		if signal_data != null and signal_data.detection != null:
			detection = signal_data.detection.duplicate(true) as DetectionComponent
		else:
			detection = DetectionComponent.new()
		_spawn["detection"] = detection
		return detection

	func _get_or_create_mobility_override() -> MobilityComponent:
		if _spawn.has("mobility") and _spawn["mobility"] != null:
			return _spawn["mobility"]
		var signal_data := _spawn["signal_data"] as SignalData
		var mobility: MobilityComponent
		if signal_data != null and signal_data.mobility != null:
			mobility = signal_data.mobility.duplicate(true) as MobilityComponent
		else:
			mobility = MobilityComponent.new()
		_spawn["mobility"] = mobility
		return mobility

	func _get_or_create_ic_override() -> ICComponent:
		if _spawn.has("ic_modules") and _spawn["ic_modules"] != null:
			return _spawn["ic_modules"]
		var signal_data := _spawn["signal_data"] as SignalData
		var ic: ICComponent
		if signal_data != null and signal_data.ic_modules != null:
			ic = signal_data.ic_modules.duplicate(true) as ICComponent
		else:
			ic = ICComponent.new()
		_spawn["ic_modules"] = ic
		return ic

const BASIC_CAMERA := preload("res://Resources/SignalPrefabs/basic_camera.tres")
const BASIC_DRONE := preload("res://Resources/SignalPrefabs/basic_drone.tres")
const BASIC_DOOR := preload("res://Resources/SignalPrefabs/basic_door.tres")
const BASIC_GUARD := preload("res://Resources/SignalPrefabs/basic_guard.tres")
const BASIC_DISRUPTOR := preload("res://Resources/SignalPrefabs/basic_disruptor.tres")
const BASIC_TERMINAL := preload("res://Resources/SignalPrefabs/basic_terminal.tres")
const PANNING_CAMERA := preload("res://Resources/SignalPrefabs/panning_camera.tres")
const COMBAT_DRONE := preload("res://Resources/SignalPrefabs/combat_drone.tres")


func get_run_id() -> String:
	return ""

func get_display_name() -> String:
	return get_run_id()

func get_spawns() -> Array[Dictionary]:
	return []

func spawn(signal_data: SignalData, cell_index: float) -> SpawnBuilder:
	return SpawnBuilder.new(self, signal_data, cell_index)

func build_runtime_signal(spawn: Dictionary) -> SignalData:
	var signal_data: SignalData = spawn["signal_data"]
	var runtime_signal := signal_data.duplicate(true) as SignalData

	if spawn.has("lane"):
		runtime_signal.lane = spawn["lane"]
	if spawn.has("system_id"):
		runtime_signal.system_id = spawn["system_id"]
	if spawn.has("display_name"):
		runtime_signal.display_name = spawn["display_name"]
	if spawn.has("spoof_id"):
		runtime_signal.spoof_id = spawn["spoof_id"]
	if spawn.has("facing_deg"):
		runtime_signal.facing_deg = float(spawn["facing_deg"])
	if spawn.has("puzzle"):
		runtime_signal.puzzle = spawn["puzzle"].duplicate(true)
	if spawn.has("ic_modules"):
		runtime_signal.ic_modules = spawn["ic_modules"].duplicate(true)
	if spawn.has("response"):
		runtime_signal.response = spawn["response"].duplicate(true)
	if spawn.has("detection"):
		runtime_signal.detection = spawn["detection"].duplicate(true)
	if spawn.has("detection_patrol_points"):
		_override_detection_patrol_points(runtime_signal, spawn["detection_patrol_points"])
	if spawn.has("mobility"):
		runtime_signal.mobility = spawn["mobility"].duplicate(true)
	if spawn.has("patrol_points"):
		_override_patrol_points(runtime_signal, spawn, spawn["patrol_points"])
	if spawn.has("disruptor"):
		runtime_signal.disruptor = spawn["disruptor"].duplicate(true)

	return runtime_signal

func make_puzzle(
	puzzle_type: PuzzleComponent.Type,
	difficulty: int = 1,
	encryption_key: String = "",
	puzzle_config: Resource = null
) -> PuzzleComponent:
	var puzzle := PuzzleComponent.new()
	puzzle.puzzle_type = puzzle_type
	puzzle.set_difficulty(difficulty)
	puzzle.encryption_key = encryption_key
	if puzzle_config != null:
		puzzle.puzzle_config = puzzle_config.duplicate(true)
	puzzle.ensure_initial_lock_state()
	return puzzle

func make_sniff_puzzle(difficulty: int = 1, sniff_config: SniffPuzzleConfig = null) -> PuzzleComponent:
	return make_puzzle(PuzzleComponent.Type.SNIFF, difficulty, "", sniff_config)

func make_fuzz_puzzle(difficulty: int = 1) -> PuzzleComponent:
	return make_puzzle(PuzzleComponent.Type.FUZZ, difficulty)

func make_decrypt_puzzle(difficulty: int = 1, encryption_key: String = "", decrypt_config: DecryptPuzzleConfig = null) -> PuzzleComponent:
	return make_puzzle(PuzzleComponent.Type.DECRYPT, difficulty, encryption_key, decrypt_config)

func make_ic(modules: Array[Resource] = []) -> ICComponent:
	var ic := ICComponent.new()
	ic.modules.assign(modules)
	return ic

func build_ic(name: StringName, difficulty: int) -> Resource:
	var ic_name := String(name).to_lower()
	var module := _create_ic_module(ic_name)
	if module == null:
		return null
	module.set_difficulty(difficulty)
	return module

func build_custom_ic(name: StringName, params: Dictionary) -> Resource:
	var ic_name := String(name).to_lower()
	var module := _create_ic_module(ic_name)
	if module == null:
		return null
	module.set_custom_fixed()
	module.apply_params(params)
	return module

func build_puzzle(name: StringName, difficulty: int) -> PuzzleComponent:
	var puzzle_name := String(name).to_lower()
	match puzzle_name:
		"sniff":
			return make_sniff_puzzle(difficulty)
		"fuzz":
			return make_fuzz_puzzle(difficulty)
		"decrypt":
			return make_decrypt_puzzle(difficulty)
	return null

func build_custom_puzzle(name: StringName, params: Dictionary) -> PuzzleComponent:
	var puzzle_name := String(name).to_lower()
	var difficulty := int(params.get("difficulty", 1))
	var uses_escalation_difficulty := bool(params.get("uses_escalation_difficulty", false))
	match puzzle_name:
		"sniff":
			var sniff_config = params.get("config", null) as SniffPuzzleConfig
			var puzzle := make_sniff_puzzle(difficulty, sniff_config)
			if not uses_escalation_difficulty:
				puzzle.set_custom_fixed()
			return puzzle
		"fuzz":
			var puzzle := make_fuzz_puzzle(difficulty)
			if not uses_escalation_difficulty:
				puzzle.set_custom_fixed()
			return puzzle
		"decrypt":
			var encryption_key := String(params.get("encryption_key", ""))
			var decrypt_config = params.get("config", null) as DecryptPuzzleConfig
			var puzzle := make_decrypt_puzzle(difficulty, encryption_key, decrypt_config)
			if not uses_escalation_difficulty:
				puzzle.set_custom_fixed()
			return puzzle
	return null

func make_response(effects: Array[Resource] = []) -> ResponseComponent:
	var response := ResponseComponent.new()
	response.effects.assign(effects)
	return response

func make_response_effect(
	effect_type: ResponseEffect.EffectType,
	amount: float,
	cadence: ResponseEffect.Cadence = ResponseEffect.Cadence.CONTINUOUS,
	delay: float = 0.0,
	sends_alert: bool = false
) -> ResponseEffect:
	var effect := ResponseEffect.new()
	effect.effect_type = effect_type
	effect.amount = amount
	effect.cadence = cadence
	effect.delay = delay
	effect.sends_alert = sends_alert
	return effect

func make_patrol_point(
	cell_offset: float,
	lane_offset: int,
	dwell_sec: float = 0.0,
	facing_deg: float = 180.0
) -> MobilityPatrolPoint:
	var point := MobilityPatrolPoint.new()
	point.cell_x = cell_offset
	point.lane = lane_offset
	point.dwell_sec = dwell_sec
	point.facing_deg = facing_deg
	return point

func make_detection_patrol_point(facing_deg: float, dwell_sec: float = 0.0) -> DetectionPatrolPoint:
	var point := DetectionPatrolPoint.new()
	point.facing_deg = facing_deg
	point.dwell_sec = dwell_sec
	return point

func make_detection_sweep(point1: Array[float], point2: Array[float], point3: Array[float] = [], point4: Array[float] = []) -> Array[DetectionPatrolPoint]:
	var route: Array[DetectionPatrolPoint] = []
	route.append(make_detection_patrol_point(point1[0], point1[1]))
	route.append(make_detection_patrol_point(point2[0], point2[1]))
	if not point3.is_empty():
		route.append(make_detection_patrol_point(point3[0], point3[1]))
	if not point4.is_empty():
		route.append(make_detection_patrol_point(point4[0], point4[1]))
	return route

# Patrol route points are authored as [cell_offset, lane_offset, dwell_sec, facing_deg].
func make_patrol_route(point1: Array[float], point2: Array[float], point3: Array[float] = [], point4: Array[float] = []) -> Array[MobilityPatrolPoint]:
	var route: Array[MobilityPatrolPoint]= []
	route.append(make_patrol_point(point1[0], int(point1[1]), point1[2], point1[3]))
	route.append(make_patrol_point(point2[0], int(point2[1]), point2[2], point2[3]))
	if not point3.is_empty():
		route.append(make_patrol_point(point3[0], int(point3[1]), point3[2], point3[3]))
	if not point4.is_empty():
		route.append(make_patrol_point(point4[0], int(point4[1]), point4[2], point4[3]))
	return route

func _override_patrol_points(runtime_signal: SignalData, spawn: Dictionary, patrol_points: Array[MobilityPatrolPoint]) -> void:
	if runtime_signal.mobility == null:
		runtime_signal.mobility = MobilityComponent.new()

	var base_cell_x := float(spawn["cell_index"])
	var base_lane := runtime_signal.lane
	runtime_signal.mobility.patrol_points.clear()
	for point in patrol_points:
		if point == null:
			continue
		var resolved_point := point.duplicate(true) as MobilityPatrolPoint
		resolved_point.cell_x = base_cell_x + point.cell_x
		resolved_point.lane = base_lane + point.lane
		runtime_signal.mobility.patrol_points.append(resolved_point)

func _override_detection_patrol_points(runtime_signal: SignalData, patrol_points: Array[DetectionPatrolPoint]) -> void:
	if runtime_signal.detection == null:
		runtime_signal.detection = DetectionComponent.new()

	runtime_signal.detection.patrol_points.clear()
	runtime_signal.detection.follow_movement_facing = false
	for point in patrol_points:
		if point == null:
			continue
		runtime_signal.detection.patrol_points.append(point.duplicate(true))

func make_mobility(
	patrol_points: Array[MobilityPatrolPoint] = [],
	move_speed_cells_per_sec: float = 0.15,
	patrol_mode: MobilityComponent.PatrolMode = MobilityComponent.PatrolMode.LOOP
) -> MobilityComponent:
	var mobility := MobilityComponent.new()
	mobility.move_speed_cells_per_sec = move_speed_cells_per_sec
	mobility.patrol_mode = patrol_mode
	mobility.patrol_points.assign(patrol_points)
	return mobility

func make_disruptor(
	investigate_duration_sec: float = -1.0,
	horizontal_range_cells: int = 0,
	severity: int = 10,
	ttl_sec: float = -1.0,
	max_alert_targets: int = 1
) -> DisruptorComponent:
	var disruptor := DisruptorComponent.new()
	disruptor.investigate_duration_sec = investigate_duration_sec
	disruptor.horizontal_range_cells = horizontal_range_cells
	disruptor.severity = severity
	disruptor.ttl_sec = ttl_sec
	disruptor.max_alert_targets = max_alert_targets
	return disruptor

func _create_ic_module(name: String) -> ICModule:
	var factory_map := {
		"reboot": func() -> ICModule: return RebootModule.new(),
		"faraday": func() -> ICModule: return FaradayModule.new(),
		"bouncer": func() -> ICModule: return BouncerModule.new(),
		"haze": func() -> ICModule: return HazeModule.new(),
		"callback": func() -> ICModule: return CallbackModule.new(),
		"trace": func() -> ICModule: return TraceModule.new(),
	}
	var factory = factory_map.get(name, null)
	if factory == null:
		return null
	return factory.call()
