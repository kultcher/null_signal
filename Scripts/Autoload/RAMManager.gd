extends Node

signal total_ram_changed(total_ram: int)
signal ram_usage_changed(used_ram: int, total_ram: int)

@export var total_ram: int = 3:
	set(value):
		total_ram = maxi(0, value)
		total_ram_changed.emit(total_ram)
		_emit_ram_usage_changed()

var _reservations: Dictionary = {}

func _ready() -> void:
	if ProgramManager != null:
		if not ProgramManager.ram_usage_changed.is_connected(_on_program_ram_usage_changed):
			ProgramManager.ram_usage_changed.connect(_on_program_ram_usage_changed)
	total_ram_changed.emit(total_ram)
	_emit_ram_usage_changed()

func reserve_ram(owner_id: StringName, amount: int = 1) -> bool:
	var normalized_amount := maxi(0, amount)
	if owner_id == StringName() or normalized_amount <= 0:
		return false
	if _reservations.has(owner_id):
		return true
	if get_available_ram() < normalized_amount:
		return false
	_reservations[owner_id] = normalized_amount
	_emit_ram_usage_changed()
	return true

func release_ram(owner_id: StringName) -> bool:
	if owner_id == StringName() or not _reservations.has(owner_id):
		return false
	_reservations.erase(owner_id)
	_emit_ram_usage_changed()
	return true

func has_reservation(owner_id: StringName) -> bool:
	return owner_id != StringName() and _reservations.has(owner_id)

func get_reserved_ram() -> int:
	var total_reserved := 0
	for amount in _reservations.values():
		total_reserved += int(amount)
	return total_reserved

func reset_run_state() -> void:
	_reservations.clear()
	_emit_ram_usage_changed()

func get_program_used_ram() -> int:
	if ProgramManager == null or not ProgramManager.has_method("get_used_ram"):
		return 0
	return ProgramManager.get_used_ram()

func get_used_ram() -> int:
	return get_program_used_ram() + get_reserved_ram()

func get_available_ram() -> int:
	return maxi(0, total_ram - get_used_ram())

func _emit_ram_usage_changed() -> void:
	ram_usage_changed.emit(get_used_ram(), total_ram)

func _on_program_ram_usage_changed(_used_ram: int, _total_ram: int) -> void:
	_emit_ram_usage_changed()
