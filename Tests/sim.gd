extends Node
# Walks the runner through the run at base speed (no stops) and records,
# per signal, the cell ranges during which the runner was inside its detection area.

var map_mode := true
var out_path := "user://sim.txt"
var speed := 0.15
var end_cell := 76.0
var contacts: Dictionary = {}
var contact_time: Dictionary = {}
var straight := false
var hold_cell := 17.5
var hold_sec := 0.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("map="):
			map_mode = a.substr(4) == "1"
		elif a.begins_with("out="):
			out_path = a.substr(4)
		elif a.begins_with("straight="):
			straight = a.substr(9) == "1"
		elif a.begins_with("hold="):
			hold_sec = float(a.substr(5))
	var run_main: Node = load("res://Scenes/run_main.tscn").instantiate()
	var tm_node := run_main.get_node("TutorialManager")
	tm_node.set_script(null)
	var timeline = run_main.get_node("SignalTimeline/TimelineManager")
	timeline.map_mode = map_mode
	add_child(run_main)
	await get_tree().process_frame
	if straight:
		var run_manager = run_main.get_node("RunManager")
		timeline.facility_layout = FacilityLayout.new(run_manager.current_run.get_rooms(), [])
	timeline.BASE_CELLS_PER_SECOND = 0.0
	timeline.cells_per_second = 0.0
	var sm = run_main.get_node("SignalTimeline/SignalManager")
	timeline.set_runner_cell(-1.0)
	var dt := 1.0 / Engine.physics_ticks_per_second
	while timeline.current_cell_pos < end_cell:
		await get_tree().physics_frame
		timeline.cells_per_second = speed
		if hold_sec > 0.0 and timeline.current_cell_pos >= hold_cell:
			timeline.cells_per_second = 0.0
			hold_sec -= dt
		get_tree().paused = false
		for sig in sm.signal_queue:
			if sig.instance_node == null:
				continue
			var dc = sig.instance_node.detection_controller
			if dc != null and dc.runner_in_vision:
				var id: String = sig.data.system_id
				contact_time[id] = contact_time.get(id, 0.0) + dt
				if not contacts.has(id):
					contacts[id] = []
				var ranges: Array = contacts[id]
				var c: float = timeline.current_cell_pos
				if ranges.is_empty() or c - ranges[-1][1] > 0.05:
					ranges.append([c, c])
				else:
					ranges[-1][1] = c
	print("SIMDONE heat=", run_main.get_node("HeatManager").get_heat(), " tier=", run_main.get_node("EscalationManager").get_active_tier_index())
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	var ids := contacts.keys()
	ids.sort()
	for id in ids:
		var parts: Array = []
		var total: float = contact_time[id]
		for r in contacts[id]:
			parts.append("%.2f-%.2f" % [r[0], r[1]])
		f.store_line("%-22s %5.1fs  %s" % [id, total, ", ".join(parts)])
	f.close()
	get_tree().quit()
