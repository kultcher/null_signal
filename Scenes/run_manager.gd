# run_manager.gd
# Handles parsing (if necessary) and loading run data

extends Node

@onready var timeline_manager = $"../SignalTimeline/TimelineManager"
@onready var signal_manager = $"../SignalTimeline/SignalManager"

@export_file("*.gd") var level_script_path := "res://Resources/RunData/AuthoredRuns/TutorialRun.gd"

var current_run: RunDefinition

# Supplied by the debug restart coordinator before this scene enters the tree.
var definition_override: RunDefinition
var debug_start_location: Dictionary = {}
var debug_free_play := false

func _ready():
	start_run()
	if not debug_start_location.is_empty():
		# Wait for TimelineManager's layout metrics and every sibling's _ready,
		# but place the runner before the first gameplay process frame.
		get_parent().ready.connect(_apply_debug_start, CONNECT_ONE_SHOT)

func _process(delta: float):
	pass

func start_run():
	if definition_override != null:
		current_run = definition_override.get_script().new()
	else:
		var level_script = load(level_script_path)
		current_run = level_script.new()
	if timeline_manager != null:
		timeline_manager.facility_layout = current_run.build_facility_layout()
	propagate()

func _apply_debug_start() -> void:
	timeline_manager.path_progress = timeline_manager.facility_layout.progress_from_location(debug_start_location)
	timeline_manager._apply_path_progress(false)
	timeline_manager.current_cell = floori(timeline_manager.current_cell_pos)
	timeline_manager.last_emitted_cell = timeline_manager.current_cell
	signal_manager.update_signal_position()

func propagate():
	for spawn in current_run.get_spawns():
		signal_manager.spawn_signal_data(current_run.build_runtime_signal(spawn), spawn["cell_index"])

func get_run_id() -> String:
	if current_run == null:
		return ""
	return current_run.get_run_id()

func get_display_name() -> String:
	if current_run == null:
		return ""
	return current_run.get_display_name()


func _on_temp_quit_button_button_down() -> void:
	get_tree().quit()
