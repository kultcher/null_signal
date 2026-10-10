# signal_manager.gd
# Manages Signals and tracks their position on the Timeline

extends Node2D

@onready var timeline_manager = $"../TimelineManager"
@onready var window_manager = $"../../WindowManager"
@onready var terminal_window = $"../../WorkspaceAnchor/TerminalWindow"
@onready var scan_controller = $"../ScanController"
@onready var escalation_manager = $"../../EscalationManager"
@onready var spawner = SignalSpawner.new()

var signal_scene = preload("res://Scenes/signal_entity.tscn")

var signal_queue: Array[ActiveSignal] = []

func _ready():
	CommandDispatch.signal_manager = self
	GlobalEvents.escalation_state_changed.connect(_escalate_signal_difficulty)
	if terminal_window != null:
		if not terminal_window.session_activated.is_connected(_on_terminal_session_visual_changed):
			terminal_window.session_activated.connect(_on_terminal_session_visual_changed)
		if not terminal_window.session_deactivated.is_connected(_on_terminal_session_visual_changed):
			terminal_window.session_deactivated.connect(_on_terminal_session_visual_changed)
		if not terminal_window.session_closed.is_connected(_on_terminal_session_visual_changed):
			terminal_window.session_closed.connect(_on_terminal_session_visual_changed)
		if not terminal_window.session_line_display_mode_changed.is_connected(_on_session_line_display_mode_changed):
			terminal_window.session_line_display_mode_changed.connect(_on_session_line_display_mode_changed)

func _exit_tree() -> void:
	for active_sig in signal_queue:
		active_sig.release_run_state()

func get_active_signal(display_name: String):
	print("Search queue for: ", display_name)
	for sig in signal_queue:
		if sig.data.display_name == display_name:
			return sig

func get_signal_by_system_id(system_id: String) -> ActiveSignal:
	for sig in signal_queue:
		if sig != null and sig.data != null and sig.data.system_id == system_id:
			return sig
	if escalation_manager != null and escalation_manager.has_method("get_signal_by_system_id"):
		return escalation_manager.get_signal_by_system_id(system_id)
	return null

func has_signal_in_network(system_id: String) -> bool:
	return get_signal_by_system_id(system_id) != null

func is_signal_in_range(system_id: String) -> bool:
	var sig := get_signal_by_system_id(system_id)
	return sig != null and sig.instance_node != null and is_signal_within_interaction_range(sig)

func get_horizontal_runner_distance_cells(active_sig: ActiveSignal) -> float:
	if active_sig == null or timeline_manager == null:
		return INF
	var signal_cell_index := active_sig.start_cell_index
	if active_sig.runtime_position_initialized:
		signal_cell_index = active_sig.runtime_cell_x
	return absf(signal_cell_index - timeline_manager.current_cell_pos)

func is_signal_within_interaction_range(active_sig: ActiveSignal) -> bool:
	if active_sig == null or timeline_manager == null:
		return false
	if active_sig.data != null and active_sig.data.type == SignalData.Type.ESCALATION:
		return true
	return get_horizontal_runner_distance_cells(active_sig) <= timeline_manager.signal_interaction_range_cells
	
func _process(delta):
	update_signal_position()

func spawn_signal_data(data: SignalData, cell_index: float):
	var new_signal = ActiveSignal.new()
	new_signal.data = data
	new_signal.start_cell_index = cell_index
	new_signal.setup()
	new_signal.generate_scan_layers()
	signal_queue.append(new_signal)

func _escalate_signal_difficulty(idx: int = 0, new_tier: int = 0) -> void:
	for s in signal_queue:
		if s.instance_node: continue		# skip if on screen
		if s.data.puzzle:
			s.data.puzzle.apply_escalation(new_tier)
			print("Upgrading puzzle on " + s.data.display_name)
		if not s.data.ic_modules: continue
		if s.data.ic_modules.modules.size() > 0:
			for m in s.data.ic_modules.modules:
				m.apply_escalation(new_tier)

func update_signal_position():
	for active_sig in signal_queue:
		var signal_cell_index := active_sig.start_cell_index
		var signal_lane := float(active_sig.data.lane)
		if active_sig.runtime_position_initialized:
			signal_cell_index = active_sig.runtime_cell_x
			signal_lane = active_sig.runtime_lane_pos

		var visual_x: float = timeline_manager.cell_to_screen_x(signal_cell_index)
		# Signals only exist on the feed of the section they were placed in.
		var in_section: bool = timeline_manager.is_cell_in_current_section(active_sig.start_cell_index)
		var is_on_screen = in_section and visual_x > -200 and visual_x < timeline_manager.screen_width + 200
		
		if is_on_screen:
			if active_sig.instance_node == null:
				var new_node = signal_scene.instantiate()
				add_child(new_node)
				new_node.setup(active_sig)
				new_node.signal_interaction.connect(_on_signal_left_clicked)
				new_node.scan_toggle_requested.connect(_on_signal_right_clicked)
				new_node.tooltip_lock_requested.connect(_on_signal_middle_clicked)
				new_node.hover_started.connect(_on_signal_mouse_enter)
				new_node.hover_ended.connect(_on_signal_mouse_exit)
				active_sig.instance_node = new_node
				if scan_controller != null and scan_controller.has_method("sync_signal_queue_visuals"):
					scan_controller.sync_signal_queue_visuals()
			
			var visual_y: float = timeline_manager.lane_to_y(signal_lane)
			var render_offset := active_sig.runtime_render_offset
			active_sig.instance_node.position = Vector2(visual_x, visual_y) + render_offset
			
		else:
			if (visual_x < -200 or not in_section) and active_sig.instance_node != null:
				if terminal_window != null:
					terminal_window.hide_tab_for_signal(active_sig)
				if scan_controller != null:
					scan_controller.notify_signal_despawned(active_sig)
				if window_manager != null:
					window_manager.close_puzzles_for_signal(active_sig)
				active_sig.instance_node.queue_free()
				active_sig.instance_node = null

func hide_signals():
	hide()

func show_signals():
	show()


func _on_signal_left_clicked(active_sig: ActiveSignal):
	if not GlobalEvents.is_tutorial_feature_enabled("connect"):
		return
	if terminal_window == null:
		return
	terminal_window.access_signal_via_click(active_sig)
	
func _on_signal_mouse_enter(signal_entered: ActiveSignal):
	if not GlobalEvents.is_tutorial_feature_enabled("scan"):
		return
	if not is_signal_within_interaction_range(signal_entered):
		return
	if signal_entered != null and signal_entered.instance_node != null:
		signal_entered.instance_node.set_hover_highlight(true)
		signal_entered.instance_node.show_hover_tooltip()

func _on_signal_right_clicked(signal_clicked: ActiveSignal):
	if not GlobalEvents.is_tutorial_feature_enabled("scan"):
		return
	if not is_signal_within_interaction_range(signal_clicked):
		return
	if scan_controller != null:
		scan_controller.toggle_scan(signal_clicked)

func _on_signal_middle_clicked(signal_clicked: ActiveSignal):
	if not GlobalEvents.is_tutorial_feature_enabled("scan"):
		return
	if not is_signal_within_interaction_range(signal_clicked):
		return
	if scan_controller != null:
		scan_controller.toggle_lock(signal_clicked)
	
func _on_signal_mouse_exit(signal_exited: ActiveSignal):
	if signal_exited != null and signal_exited.instance_node != null:
		signal_exited.instance_node.set_hover_highlight(false)
		signal_exited.instance_node.fade_tooltip_body()

func _on_terminal_session_visual_changed(active_sig: ActiveSignal) -> void:
	if active_sig == null or active_sig.instance_node == null or terminal_window == null:
		return
	active_sig.instance_node.set_session_indicator_state(
		terminal_window.get_session_visual_state(active_sig)
	)
	active_sig.instance_node.refresh_session_indicator_geometry()

func _on_session_line_display_mode_changed() -> void:
	if terminal_window == null:
		return
	for active_sig in signal_queue:
		if active_sig == null or active_sig.instance_node == null:
			continue
		active_sig.instance_node.refresh_session_indicator_geometry()
		active_sig.instance_node.set_session_indicator_state(
			terminal_window.get_session_visual_state(active_sig)
		)
