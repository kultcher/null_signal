# ActiveSignal.gd
# Wrapper for currently on-screen Signals

class_name ActiveSignal extends RefCounted

const COLOR_STATUS_UNKNOWN := Color("613d82ff")
const COLOR_STATUS_SCANNING := Color("009632ff")
const COLOR_STATUS_COMPLETE := Color("00fa64ff")
const COLOR_STATUS_PARTIAL := Color("c1a126")

const COLOR_LOCK_OPEN := Color("0096faff")
const COLOR_LOCK_LOCKED := Color("ff0000ff")
const COLOR_LOCK_HACKED := Color("0096faff")

var data: SignalData
var start_cell_index: float
var instance_node: Node2D = null # Visual

enum TooltipIconState {
	UNKNOWN_SCAN,
	UNKNOWN_LOCK,
	SCANNING,
	PARTIAL,
	COMPLETE,
	OPEN,
	LOCKED,
	HACKED,
	NO_IC,
	ACTIVE_IC
}

class ScanLayer:
	var name: String         # Internal ID (e.g. "TYPE", "IC_CLOAK")
	var duration: float      # How long to unlock this specific layer
	var revealed: bool = false
	var description: String  # Text for the UI later (e.g. "Hidden IC Module")

var scan_layers: Array[ScanLayer] = []
var current_scan_index: int = 0
var current_layer_progress: float = 0.0
var is_being_scanned: bool = false
var is_tooltip_collapsed: bool = true

var is_disabled: bool = false

var terminal_session: TerminalSession = null

# Runtime movement state for mobile signals. These are timeline-space
# coordinates; screen-space conversion stays in SignalManager.
var runtime_position_initialized: bool = false
var runtime_cell_x: float = 0.0
var runtime_lane: int = 2
var runtime_lane_pos: float = 2.0
var runtime_body_facing_deg: float = 180.0
var runtime_detection_facing_deg: float = 180.0
var runtime_detection_paused: bool = false
var runtime_render_offset: Vector2 = Vector2.ZERO

func setup():
	# Assign name based on possible obfuscations
	if data.spoof_id != "":
		data.display_name = data.spoof_id
	if !data.display_name:
		data.display_name = data.system_id
	if data.puzzle:
		data.puzzle.ensure_initial_lock_state()
	if data.type == SignalData.Type.DOOR:
		set_door_locked(data.door_locked)
	if data.ic_modules != null:
		data.ic_modules.notify_initialized(self)
	if data.escalation != null:
		data.escalation.initialize(self)

func disable_signal():
	is_disabled = true
	if CommandDispatch.window_manager != null:
		CommandDispatch.window_manager.close_puzzles_for_signal(self)
	if instance_node != null:
		instance_node.detection_controller.disable_vision()
		instance_node.update_visuals()
	if data.ic_modules:
		data.ic_modules.notify_disabled(self)
	if data.escalation != null:
		data.escalation.on_disabled(self)
		GlobalEvents.escalation_signal_disabled.emit(self)

func enable_signal():
	is_disabled = false
	if instance_node != null:
		instance_node.detection_controller.enable_vision()
		instance_node.update_visuals()
	if data.ic_modules:
		data.ic_modules.notify_enabled(self)
	if data.escalation != null:
		data.escalation.on_enabled(self)

func generate_scan_layers():
	scan_layers.clear()
	build_id_layer()
	build_puzzle_layer()
	build_ic_layer()

# Forget everything scanned so far (used by Shy IC).
func reset_scan_progress() -> void:
	for layer in scan_layers:
		layer.revealed = false
	current_scan_index = 0
	current_layer_progress = 0.0

func set_door_locked(locked: bool) -> void:
	if data == null or data.type != SignalData.Type.DOOR:
		return

	data.door_locked = locked
	data.use_alternate_visuals = not locked
	if data.detection != null:
		if locked:
			data.detection.enable_detection()
		else:
			data.detection.disable_detection()
	if data.response != null:
		data.response.reset_delay_state(self, not locked)
	if instance_node != null:
		instance_node.update_visuals()
		
func build_id_layer(difficulty_modifier: float = 1.0):
	var l0 = ScanLayer.new()
	l0.name = "IDENTITY"
	l0.duration = 0.25 * difficulty_modifier
	l0.description = "Type: " + data.identity_dict[data.type]
	# Check data.visual_state. If it's already REVEALED, mark this true immediately
	#if data.visual_state == SignalData.VisualState.REVEALED:
	#	l0.revealed = true
	#	current_scan_index = 1 # Skip to next
	scan_layers.append(l0)

func build_puzzle_layer(difficulty_modifier: float = 1.0):
	var l3 = ScanLayer.new()
	l3.name = "ACCESS"
	l3.duration = 0.5
	if data.puzzle: l3.description = "Access: " + data.puzzle.get_desc()
	else: l3.description = "Access: Open"
	scan_layers.append(l3)

func build_ic_layer(difficulty_modifier: float = 1.0):
	if data.ic_modules == null: return
	if data.ic_modules.modules.is_empty():
		var no_ic_layer = ScanLayer.new()
		no_ic_layer.name = "IC"
		no_ic_layer.duration = 0.5 * difficulty_modifier
		no_ic_layer.description = "IC: None"
		scan_layers.append(no_ic_layer)
		return
	for module in data.ic_modules.modules:
		if module == null:
			continue
		var ic_layer = ScanLayer.new()
		ic_layer.name = "IC"
		ic_layer.duration = 0.5 * difficulty_modifier
		ic_layer.description = "IC: " + module.get_desc()
		scan_layers.append(ic_layer)

func get_revealed_scan_descriptions() -> Array[String]:
	var revealed_lines: Array[String] = []
	for i in range(scan_layers.size()):
		var layer: ScanLayer = scan_layers[i]
		if _is_scan_layer_effectively_revealed(layer, i):
			revealed_lines.append(layer.description)
	return revealed_lines

func get_revealed_scan_descriptions_for_layer(layer_name: String) -> Array[String]:
	var revealed_lines: Array[String] = []
	for i in range(scan_layers.size()):
		var layer: ScanLayer = scan_layers[i]
		if layer.name == layer_name and _is_scan_layer_effectively_revealed(layer, i):
			revealed_lines.append(layer.description)
	return revealed_lines

func is_scan_layer_revealed(layer_name: String) -> bool:
	for i in range(scan_layers.size()):
		var layer: ScanLayer = scan_layers[i]
		if layer.name == layer_name:
			return _is_scan_layer_effectively_revealed(layer, i)
	return false

func get_total_scan_layer_count() -> int:
	return scan_layers.size()

func get_revealed_scan_layer_count() -> int:
	var revealed_count := 0
	for i in range(scan_layers.size()):
		var layer: ScanLayer = scan_layers[i]
		if _is_scan_layer_effectively_revealed(layer, i):
			revealed_count += 1
	return revealed_count

func get_scan_layer_count(layer_name: String) -> int:
	var layer_count := 0
	for layer in scan_layers:
		if layer.name == layer_name:
			layer_count += 1
	return layer_count

func get_revealed_scan_layer_count_for(layer_name: String) -> int:
	var revealed_count := 0
	for layer in scan_layers:
		if layer.name == layer_name and _is_scan_layer_effectively_revealed(layer):
			revealed_count += 1
	return revealed_count

func is_ic_module_revealed(module_index: int) -> bool:
	if module_index < 0:
		return false
	var ic_module_idx := 0
	for i in range(scan_layers.size()):
		var layer: ScanLayer = scan_layers[i]
		if layer.name != "IC":
			continue
		if ic_module_idx == module_index:
			return _is_scan_layer_effectively_revealed(layer, i)
		ic_module_idx += 1
	return false

func _is_scan_layer_effectively_revealed(layer: ScanLayer, layer_index: int = -1) -> bool:
	if layer == null:
		return false
	if layer.revealed:
		return true
	if current_scan_index >= scan_layers.size():
		return true
	if layer_index < 0:
		layer_index = scan_layers.find(layer)
	if layer_index == -1:
		return false
	return layer_index < current_scan_index

func get_scan_status_icon_state() -> int:
	if is_being_scanned and current_scan_index < scan_layers.size():
		return TooltipIconState.SCANNING
	if scan_layers.is_empty() or current_scan_index >= scan_layers.size():
		return TooltipIconState.COMPLETE
	if current_scan_index > 0:
		return TooltipIconState.PARTIAL
	return TooltipIconState.UNKNOWN_SCAN

func get_lock_status_icon_state() -> int:
	if not is_scan_layer_revealed("ACCESS"):
		return TooltipIconState.UNKNOWN_LOCK
	if data == null or data.puzzle == null:
		return TooltipIconState.OPEN
	if data.puzzle.puzzle_locked:
		return TooltipIconState.LOCKED
	return TooltipIconState.HACKED

func get_ic_status_icon_state() -> int:
	if not is_scan_layer_revealed("IC"):
		return TooltipIconState.UNKNOWN_SCAN
	if data == null or data.ic_modules == null or data.ic_modules.modules.size() <= 0:
		return TooltipIconState.NO_IC
	return TooltipIconState.ACTIVE_IC

func get_scan_status_label_text() -> String:
	var scan_state := get_scan_status_icon_state()
	match scan_state:
		TooltipIconState.SCANNING:
			return "Scan: SCANNING"
		TooltipIconState.PARTIAL:
			return "Scan: PARTIAL"
		TooltipIconState.COMPLETE:
			return "Scan: COMPLETE"
	return "Scan: UNSCANNED"

func get_lock_status_label_text() -> String:
	if not is_scan_layer_revealed("ACCESS"):
		return "Lock: Unverified"
	if data == null:
		return "Lock: Unknown"
	if data.puzzle != null:
		return "Lock: " + data.puzzle.get_desc()
	return "Lock: Open"

func get_ic_status_detail_text() -> String:
	if not is_scan_layer_revealed("IC"):
		return "IC: Unknown"
	var revealed_ic_lines := get_revealed_scan_descriptions_for_layer("IC")
	if revealed_ic_lines.is_empty():
		return "IC: Unknown"
	var descriptions: Array[String] = []
	for line in revealed_ic_lines:
		var parts := line.split(":", false, 1)
		if parts.size() > 1:
			descriptions.append(parts[1].strip_edges())
		else:
			descriptions.append(line.strip_edges())
	return "IC: " + " | ".join(descriptions)

func get_ic_scan_progress_value() -> float:
	var total_ic_layers = max(1, get_scan_layer_count("IC"))
	var revealed_ic_layers := float(get_revealed_scan_layer_count_for("IC"))
	if is_being_scanned and current_scan_index < scan_layers.size():
		var current_layer = scan_layers[current_scan_index]
		if current_layer.name == "IC" and current_layer.duration > 0.0:
			var current_fraction := clampf(current_layer_progress / current_layer.duration, 0.0, 1.0)
			return minf(float(total_ic_layers), revealed_ic_layers + current_fraction)
	return revealed_ic_layers

func get_ic_scan_progress_max() -> int:
	return max(1, get_scan_layer_count("IC"))

func get_ic_progress_color() -> Color:
	if not is_scan_layer_revealed("IC") and not (is_being_scanned and current_scan_index < scan_layers.size() and scan_layers[current_scan_index].name == "IC"):
		return COLOR_STATUS_UNKNOWN
	if data == null or data.ic_modules == null or data.ic_modules.modules.size() <= 0:
		return COLOR_STATUS_COMPLETE
	return COLOR_LOCK_LOCKED

func get_ic_status_label_text() -> String:
	return get_ic_status_detail_text()

func get_scan_status_color() -> Color:
	var scan_state := get_scan_status_icon_state()
	match scan_state:
		TooltipIconState.SCANNING:
			return COLOR_STATUS_SCANNING
		TooltipIconState.PARTIAL:
			return COLOR_STATUS_PARTIAL
		TooltipIconState.COMPLETE:
			return COLOR_STATUS_COMPLETE
	return COLOR_STATUS_UNKNOWN

func get_lock_status_color() -> Color:
	var lock_state := get_lock_status_icon_state()
	match lock_state:
		TooltipIconState.OPEN:
			return COLOR_LOCK_OPEN
		TooltipIconState.LOCKED:
			return COLOR_LOCK_LOCKED
		TooltipIconState.HACKED:
			return COLOR_LOCK_HACKED
	return COLOR_STATUS_UNKNOWN

func get_ic_status_color() -> Color:
	var ic_state := get_ic_status_icon_state()
	match ic_state:
		TooltipIconState.NO_IC:
			return COLOR_STATUS_COMPLETE
		TooltipIconState.ACTIVE_IC:
			return COLOR_LOCK_LOCKED
	return COLOR_STATUS_UNKNOWN
