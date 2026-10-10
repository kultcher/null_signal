# Temporary coordinator outside the run scene. Deferred replacement prevents
# freeing the viewer while it is still handling input or a button signal.
extends Node

var _old_run: Node
var _new_run: Node

static func request(run_root: Node, definition: RunDefinition, path: String, location: Dictionary) -> bool:
	if not OS.is_debug_build() or definition == null or location.is_empty():
		return false
	var scene_path := run_root.scene_file_path
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return false
	var next_run := scene.instantiate()
	var manager = next_run.get_node("RunManager")
	manager.definition_override = definition
	manager.level_script_path = path
	manager.debug_start_location = location.duplicate()
	manager.debug_free_play = true
	next_run.process_mode = Node.PROCESS_MODE_PAUSABLE
	var coordinator = load("res://Scripts/Debug/debug_run_restart.gd").new()
	coordinator._old_run = run_root
	coordinator._new_run = next_run
	coordinator.process_mode = Node.PROCESS_MODE_ALWAYS
	run_root.get_tree().root.add_child(coordinator)
	coordinator.call_deferred("_replace_run")
	return true

func _replace_run() -> void:
	if not is_instance_valid(_old_run) or _old_run.is_queued_for_deletion():
		_new_run.free()
		queue_free()
		return
	var tree := get_tree()
	var host := _old_run.get_parent()
	var was_current := tree.current_scene == _old_run
	_old_run.free()
	# Scene-owned state (health, heat, scans, terminals, guards, IC) has gone.
	# Reset the autoload state which would otherwise survive scene replacement.
	CommandDispatch.clear_run_references()
	GlobalEvents.reset_run_state()
	ActionResolver.reset_run_state()
	RAMManager.reset_run_state()
	ProgramManager.reset_run_state()
	Engine.time_scale = 1.0
	tree.paused = false
	host.add_child(_new_run)
	if was_current:
		tree.current_scene = _new_run
	queue_free()
