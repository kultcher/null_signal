extends Node

signal total_ram_changed(total_ram: int)
signal ram_usage_changed(used_ram: int, total_ram: int)
signal program_installed(program_instance: ProgramInstance)
signal program_removed(program_instance: ProgramInstance)
signal program_state_changed(program_instance: ProgramInstance, old_state: int, new_state: int)
signal program_use_requested(program_instance: ProgramInstance)
signal program_became_ready(program_instance: ProgramInstance)
signal program_executed(program_instance: ProgramInstance)
signal program_cleanup_finished(program_instance: ProgramInstance)

@export var total_ram: int = 3:
	set(value):
		total_ram = maxi(0, value)
		total_ram_changed.emit(total_ram)
		_emit_ram_usage_changed()

var _programs: Array[ProgramInstance] = []

func _ready() -> void:
	if not total_ram_changed.is_connected(GlobalEvents.program_total_ram_changed.emit):
		total_ram_changed.connect(GlobalEvents.program_total_ram_changed.emit)
	if not ram_usage_changed.is_connected(GlobalEvents.program_ram_changed.emit):
		ram_usage_changed.connect(GlobalEvents.program_ram_changed.emit)
	if not program_installed.is_connected(GlobalEvents.program_installed.emit):
		program_installed.connect(GlobalEvents.program_installed.emit)
	if not program_removed.is_connected(GlobalEvents.program_removed.emit):
		program_removed.connect(GlobalEvents.program_removed.emit)
	if not program_state_changed.is_connected(GlobalEvents.program_state_changed.emit):
		program_state_changed.connect(GlobalEvents.program_state_changed.emit)
	if not program_use_requested.is_connected(GlobalEvents.program_use_requested.emit):
		program_use_requested.connect(GlobalEvents.program_use_requested.emit)
	if not program_became_ready.is_connected(GlobalEvents.program_became_ready.emit):
		program_became_ready.connect(GlobalEvents.program_became_ready.emit)
	if not program_executed.is_connected(GlobalEvents.program_executed.emit):
		program_executed.connect(GlobalEvents.program_executed.emit)
	if not program_cleanup_finished.is_connected(GlobalEvents.program_cleanup_finished.emit):
		program_cleanup_finished.connect(GlobalEvents.program_cleanup_finished.emit)
	if RAMManager != null and not RAMManager.total_ram_changed.is_connected(_on_ram_manager_total_changed):
		RAMManager.total_ram_changed.connect(_on_ram_manager_total_changed)

	_install_player_loadout()
	if RAMManager != null:
		total_ram = RAMManager.total_ram
	total_ram_changed.emit(total_ram)
	_emit_ram_usage_changed()

func _process(delta: float) -> void:
	for program in _programs:
		if program == null:
			continue
		var old_state := program.state
		if program.tick(delta):
			program_state_changed.emit(program, old_state, program.state)
			_emit_ram_usage_changed()
			_handle_state_transition_notices(program, old_state, program.state)

func install_program(definition: ProgramDefinition) -> ProgramInstance:
	if definition == null:
		return null
	var instance := ProgramInstance.new(definition)
	_programs.append(instance)
	program_installed.emit(instance)
	return instance

func remove_program(program_id: StringName) -> bool:
	var instance := get_program(program_id)
	if instance == null:
		return false
	_programs.erase(instance)
	program_removed.emit(instance)
	_emit_ram_usage_changed()
	return true

func get_program(program_id: StringName) -> ProgramInstance:
	for program in _programs:
		if program != null and program.get_program_id() == program_id:
			return program
	return null

func get_programs() -> Array[ProgramInstance]:
	return _programs.duplicate()

func request_load(program_id: StringName) -> bool:
	var program := get_program(program_id)
	if program == null or program.state != ProgramInstance.State.DOCKED:
		return false
	if not _can_afford_state_transition(program, ProgramInstance.State.LOADING):
		return false

	var old_state := program.state
	program.begin_loading()
	program_state_changed.emit(program, old_state, program.state)
	_emit_ram_usage_changed()
	return true

func request_unload(program_id: StringName) -> bool:
	var program := get_program(program_id)
	if program == null:
		return false
	match program.state:
		ProgramInstance.State.LOADING, ProgramInstance.State.RUNNING:
			var old_state := program.state
			program.begin_cleanup(program.was_used)
			program_state_changed.emit(program, old_state, program.state)
			_emit_ram_usage_changed()
			return true
		_:
			return false

func mark_program_used(program_id: StringName) -> bool:
	var program := get_program(program_id)
	if program == null or program.state != ProgramInstance.State.RUNNING:
		return false

	program.mark_used()
	var old_state := program.state
	program.begin_cleanup(true)
	program_state_changed.emit(program, old_state, program.state)
	_emit_ram_usage_changed()
	program_executed.emit(program)
	_print_program_notice(_get_program_notice(program, &"executed"))
	return true

func request_use(program_id: StringName) -> bool:
	var program := get_program(program_id)
	if program == null or program.state != ProgramInstance.State.RUNNING:
		return false
	if program.definition == null or program.definition.kind != ProgramDefinition.ProgramKind.ACTIVE:
		return false
	if not program.definition.is_manual_activation():
		return false

	program_use_requested.emit(program)
	return true

func get_used_ram() -> int:
	var used_ram := 0
	for program in _programs:
		if program == null:
			continue
		used_ram += program.get_current_ram_cost()
	return used_ram

func get_available_ram() -> int:
	if RAMManager != null and RAMManager.has_method("get_available_ram"):
		return RAMManager.get_available_ram()
	return maxi(0, total_ram - get_used_ram())

func preprocess_action(action_context: ActionContext) -> void:
	for program in _programs:
		if program == null:
			continue
		program.preprocess_action(action_context)

func postprocess_action(action_context: ActionContext) -> void:
	for program in _programs:
		if program == null:
			continue
		program.postprocess_action(action_context)

func print_program_notice(text: String) -> void:
	if text.is_empty():
		return
	if CommandDispatch == null or CommandDispatch.terminal_window == null:
		return
	if CommandDispatch.terminal_window.has_method("print_transient"):
		CommandDispatch.terminal_window.print_transient(text)

func _can_afford_state_transition(program: ProgramInstance, target_state: int) -> bool:
	if program == null or program.definition == null:
		return false
	var target_cost := program.definition.get_phase_ram_cost(target_state)
	var projected_program_ram := get_used_ram() - program.get_current_ram_cost() + target_cost
	var reserved_ram := RAMManager.get_reserved_ram() if RAMManager != null and RAMManager.has_method("get_reserved_ram") else 0
	var ram_cap := RAMManager.total_ram if RAMManager != null else total_ram
	return projected_program_ram + reserved_ram <= ram_cap

func _emit_ram_usage_changed() -> void:
	var ram_cap := RAMManager.total_ram if RAMManager != null else total_ram
	ram_usage_changed.emit(get_used_ram(), ram_cap)

func _handle_state_transition_notices(program: ProgramInstance, old_state: int, new_state: int) -> void:
	if program == null:
		return
	if old_state == ProgramInstance.State.LOADING and new_state == ProgramInstance.State.RUNNING:
		program_became_ready.emit(program)
		_print_program_notice(_get_program_notice(program, &"ready"))
		return
	if old_state == ProgramInstance.State.CLEANUP and new_state == ProgramInstance.State.DOCKED:
		program_cleanup_finished.emit(program)
		_print_program_notice(_get_program_notice(program, &"cleanup"))

func _get_program_notice(program: ProgramInstance, notice_type: StringName) -> String:
	if program == null or program.definition == null:
		return ""
	match notice_type:
		&"ready":
			return program.definition.get_ready_notice(program)
		&"executed":
			return program.definition.get_executed_notice(program)
		&"cleanup":
			return program.definition.get_cleanup_finished_notice(program)
		_:
			return ""

func _print_program_notice(text: String) -> void:
	print_program_notice(text)

func _install_player_loadout() -> void:
	_programs.clear()
	if PlayerData == null or not PlayerData.has_method("get_equipped_programs"):
		return
	for definition in PlayerData.get_equipped_programs():
		install_program(definition)

func reset_run_state() -> void:
	_install_player_loadout()
	_emit_ram_usage_changed()

func _on_ram_manager_total_changed(new_total_ram: int) -> void:
	total_ram = maxi(0, new_total_ram)
	total_ram_changed.emit(total_ram)
	_emit_ram_usage_changed()
