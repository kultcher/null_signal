# run_manager.gd
# Handles parsing (if necessary) and loading run data

extends Node

@onready var timeline_manager = $"../SignalTimeline/TimelineManager"
@onready var signal_manager = $"../SignalTimeline/SignalManager"

@export_file("*.gd") var level_script_path := "res://Resources/RunData/AuthoredRuns/TutorialRun.gd"

var current_run: RunDefinition

func _ready():
	start_run()

func _process(delta: float):
	pass

func start_run():
	var level_script = load(level_script_path)
	current_run = level_script.new()
	if timeline_manager != null:
		timeline_manager.facility_layout = current_run.build_facility_layout()
	propagate()

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
