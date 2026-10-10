# Read-only authored-run preview. Owns its projection and duplicated resources;
# it never updates TimelineManager or the live SignalManager.
extends CanvasLayer

const BASE_CELL_PX := 240.0
const BASE_LANE_PX := 90.0
const MIN_ZOOM := 0.025
const MAX_ZOOM := 4.0

@onready var panel: Control = $Panel
@onready var map_view: Control = $Panel/MapView
@onready var map_layer = $Panel/MapView/FacilityMap
@onready var overlay = $Panel/MapView/Overlay
@onready var run_picker: OptionButton = $Panel/Header/Controls/Run
@onready var section_picker: OptionButton = $Panel/Header/Controls/Section
@onready var status: Label = $Panel/Status
@onready var coordinates: Label = $Panel/Coordinates
@onready var inspector: Label = $Panel/Inspector/Scroll/Details
@onready var distance_toggle: CheckButton = $Panel/Header/Overlays/Distance
@onready var route_toggle: CheckButton = $Panel/Header/Overlays/Route
@onready var vision_toggle: CheckButton = $Panel/Header/Overlays/Vision
@onready var patrol_toggle: CheckButton = $Panel/Header/Overlays/Patrols
@onready var boundary_toggle: CheckButton = $Panel/Header/Overlays/Boundaries
@onready var labels_toggle: CheckButton = $Panel/Header/Overlays/Labels

var facility_layout: FacilityLayout
var entries: Array[Dictionary] = []
var script_path := ""
var preview_run: RunDefinition
var selected_index := -1
var section_index := -1 # -1 means all sections
var center := Vector2(0.0, 2.0)
var zoom := 1.0
var measurement: Array[Vector2] = []
var _previous_pause := false
var _dragging := false
var _run_paths: Array[String] = []
var _runner_position := Vector2.ZERO

# Projection interface used by the shared facility renderer.
var map_mode := true
var screen_width: float:
	get: return map_view.size.x
var cell_width_px: float:
	get: return BASE_CELL_PX * zoom
var lane_height: float:
	get: return BASE_LANE_PX * zoom
var current_cell_pos: float:
	get: return _runner_position.x

func _ready() -> void:
	panel.hide()
	map_layer.preview_mode = true
	map_view.resized.connect(_redraw)
	run_picker.item_selected.connect(_select_run)
	section_picker.item_selected.connect(_select_section)
	$Panel/Header/Controls/FitSection.pressed.connect(fit_section)
	$Panel/Header/Controls/FitLevel.pressed.connect(fit_level)
	$Panel/Header/Controls/Reload.pressed.connect(reload_preview)
	$Panel/Header/Controls/Close.pressed.connect(close_viewer)
	for toggle in [distance_toggle, route_toggle, vision_toggle, patrol_toggle, boundary_toggle, labels_toggle]:
		toggle.toggled.connect(func(_value: bool): _redraw())

func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			if panel.visible: close_viewer()
			else: open_viewer()
			get_viewport().set_input_as_handled()
			return
		if not panel.visible:
			return
		match event.keycode:
			KEY_ESCAPE: close_viewer()
			KEY_R: reload_preview()
			KEY_HOME:
				if event.shift_pressed: fit_level()
				else: fit_section()
			KEY_PAGEUP: _step_section(-1)
			KEY_PAGEDOWN: _step_section(1)
			KEY_DELETE:
				measurement.clear()
				_redraw()
			_: pass
		get_viewport().set_input_as_handled()
	if not panel.visible:
		return
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
		return
	var local := map_view.get_local_mouse_position()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
			_dragging = false
		if not Rect2(Vector2.ZERO, map_view.size).has_point(local):
			return
		match event.button_index:
			MOUSE_BUTTON_MIDDLE: _dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed: zoom_at(local, 1.2)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed: zoom_at(local, 1.0 / 1.2)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					if event.shift_pressed: measure_screen_point(local)
					else: select_at(local)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _dragging:
			pan_pixels(event.relative)
		if Rect2(Vector2.ZERO, map_view.size).has_point(local):
			var point := screen_to_map(local)
			coordinates.text = "CURSOR  cell %.2f | lane %.2f     ZOOM %.0f%%     %s" % [point.x, point.y, zoom * 100.0, measurement_text()]
			get_viewport().set_input_as_handled()

func open_viewer() -> void:
	if panel.visible:
		return
	_previous_pause = get_tree().paused
	get_tree().paused = true
	panel.show()
	var run_manager = get_parent().get_node("RunManager")
	var timeline = get_parent().get_node("SignalTimeline/TimelineManager")
	_runner_position = Vector2(timeline.current_cell_pos, timeline.runner_lane_pos)
	_populate_runs(run_manager.current_run.get_script().resource_path)
	if load_preview(run_manager.current_run.get_script().resource_path):
		section_index = clampi(timeline.current_section_index, 0, facility_layout.sections.size() - 1)
		_sync_sections()
		fit_section()

func close_viewer() -> void:
	if not panel.visible:
		return
	_dragging = false
	panel.hide()
	get_tree().paused = _previous_pause

func _exit_tree() -> void:
	if is_instance_valid(panel) and panel.visible:
		get_tree().paused = _previous_pause

func _populate_runs(current_path: String) -> void:
	run_picker.clear()
	_run_paths.clear()
	for filename in DirAccess.get_files_at("res://Resources/RunData/AuthoredRuns"):
		if filename.ends_with(".gd"):
			_run_paths.append("res://Resources/RunData/AuthoredRuns/" + filename)
	if not current_path in _run_paths:
		_run_paths.append(current_path)
	_run_paths.sort()
	for path in _run_paths:
		run_picker.add_item(path.get_file().get_basename())
	run_picker.select(_run_paths.find(current_path))

func load_preview(path: String) -> bool:
	# Compile a fresh script rather than replacing a cached resource that the
	# live run still owns. Parse failures leave the previous snapshot intact.
	if path.begins_with("uid://"):
		path = ResourceUID.get_id_path(ResourceUID.text_to_id(path))
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		status.text = "Cannot read %s. Previous preview retained." % path
		return false
	var script := GDScript.new()
	script.source_code = file.get_as_text()
	var error := script.reload()
	if error != OK or not script.can_instantiate():
		status.text = "Reload failed (%s). Previous preview retained; see Godot's error output." % error_string(error)
		return false
	# Check inheritance before instantiation so an unrelated script cannot
	# replace the preview or invoke its _init() here.
	var base := script.get_base_script()
	while base != null and base != preload("res://Resources/RunData/RunDefinition.gd"):
		base = base.get_base_script()
	if base == null:
		status.text = "Selected script must extend RunDefinition. Previous preview retained."
		return false
	var run: RunDefinition = script.new()
	var layout := run.build_facility_layout()
	var next_entries: Array[Dictionary] = []
	for spawn in run.get_spawns():
		if not spawn.has("signal_data") or spawn["signal_data"] == null or not spawn.has("cell_index"):
			status.text = "Invalid spawn data. Previous preview retained."
			return false
		var data := run.build_runtime_signal(spawn)
		var cell := float(spawn["cell_index"])
		next_entries.append({"data": data, "cell": cell, "section": layout.get_section_for_cell(cell).id})
	# Copy the gameplay metric once. Preview zoom never changes route length.
	var timeline = get_parent().get_node("SignalTimeline/TimelineManager")
	layout.set_lane_to_cell_scale(timeline.lane_height / timeline.cell_width_px)
	var selected_id := ""
	if selected_index >= 0 and selected_index < entries.size():
		selected_id = entries[selected_index]["data"].system_id
	var old_section_id := ""
	if facility_layout != null and section_index >= 0:
		old_section_id = facility_layout.sections[section_index].id
	preview_run = run
	facility_layout = layout
	entries = next_entries
	script_path = path
	selected_index = -1
	for i in entries.size():
		if entries[i]["data"].system_id == selected_id:
			selected_index = i
	if section_index >= 0:
		section_index = 0
		for i in layout.sections.size():
			if layout.sections[i].id == old_section_id:
				section_index = i
	_sync_sections()
	_update_inspector()
	status.text = "%s | %d signals | %d sections | Authored preview; gameplay frozen. Reload updates this preview only." % [run.get_display_name(), entries.size(), layout.sections.size()]
	_redraw()
	return true

func reload_preview() -> void:
	load_preview(script_path)

func _select_run(index: int) -> void:
	if load_preview(_run_paths[index]):
		measurement.clear()
		selected_index = -1
		fit_level()
		_update_inspector()
	else:
		run_picker.select(_run_paths.find(script_path))

func _sync_sections() -> void:
	section_picker.clear()
	section_picker.add_item("All sections")
	for section in facility_layout.sections:
		section_picker.add_item(section.label if not section.label.is_empty() else section.id)
	section_picker.select(section_index + 1)

func _select_section(index: int) -> void:
	section_index = index - 1
	section_picker.select(index)
	fit_section()

func _step_section(direction: int) -> void:
	if facility_layout == null:
		return
	section_index = clampi(section_index + direction, 0, facility_layout.sections.size() - 1)
	section_picker.select(section_index + 1)
	fit_section()

func visible_sections() -> Array[FacilitySection]:
	if facility_layout == null:
		return []
	if section_index < 0:
		return facility_layout.sections
	return [facility_layout.sections[section_index]]

func visible_entries() -> Array[Dictionary]:
	if section_index < 0:
		return entries
	var result: Array[Dictionary] = []
	for entry in entries:
		if entry["section"] == facility_layout.sections[section_index].id:
			result.append(entry)
	return result

func fit_level() -> void:
	section_index = -1
	section_picker.select(0)
	fit_section()

func fit_section() -> void:
	if facility_layout == null:
		return
	var bounds := get_content_bounds()
	center = bounds.get_center()
	var available := get_map_rect().size - Vector2(100.0, 80.0)
	zoom = clampf(minf(available.x / (maxf(1.0, bounds.size.x) * BASE_CELL_PX), available.y / (maxf(1.0, bounds.size.y) * BASE_LANE_PX)), MIN_ZOOM, MAX_ZOOM)
	_redraw()

func get_content_bounds() -> Rect2:
	var bounds := Rect2()
	var initialized := false
	for section in visible_sections():
		# The legacy fallback route is infinite for authoring purposes; fit its
		# actual signals instead of 20,000 cells of empty space.
		if section.id != "default":
			for point in section.path_points:
				if not initialized:
					bounds = Rect2(point, Vector2.ZERO)
					initialized = true
				else: bounds = bounds.expand(point)
			for room in facility_layout.get_rooms_in_section(section):
				var rect := Rect2(room.start_cell, room.lane_top, room.end_cell - room.start_cell, room.lane_bottom - room.lane_top)
				if not initialized:
					bounds = rect
					initialized = true
				else: bounds = bounds.merge(rect)
	for entry in visible_entries():
		var data: SignalData = entry["data"]
		var point := Vector2(entry["cell"], data.lane)
		if not initialized:
			bounds = Rect2(point, Vector2.ZERO)
			initialized = true
		else: bounds = bounds.expand(point)
		if data.mobility != null:
			for patrol in data.mobility.patrol_points:
				bounds = bounds.expand(Vector2(patrol.cell_x, patrol.lane))
	return bounds.grow(0.5) if initialized else Rect2(-1.0, -0.5, 10.0, 5.0)

func pan_pixels(delta: Vector2) -> void:
	center -= Vector2(delta.x / cell_width_px, delta.y / lane_height)
	_redraw()

func zoom_at(screen_point: Vector2, factor: float) -> void:
	var before := screen_to_map(screen_point)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	center += before - screen_to_map(screen_point)
	_redraw()

func get_map_rect() -> Rect2:
	return Rect2(52.0, 30.0, maxf(1.0, map_view.size.x - 52.0), maxf(1.0, map_view.size.y - 30.0))

func cell_lane_to_screen(cell: float, lane: float) -> Vector2:
	return get_map_rect().get_center() + Vector2((cell - center.x) * cell_width_px, (lane - center.y) * lane_height)

func screen_to_map(point: Vector2) -> Vector2:
	var delta := point - get_map_rect().get_center()
	return center + Vector2(delta.x / cell_width_px, delta.y / lane_height)

func cell_to_screen_x(cell: float) -> float:
	return cell_lane_to_screen(cell, center.y).x

func screen_x_to_cell(x: float) -> float:
	return screen_to_map(Vector2(x, 0.0)).x

func lane_to_y(lane: float) -> float:
	return cell_lane_to_screen(center.x, lane).y

func get_current_section() -> FacilitySection:
	return facility_layout.sections[maxi(0, section_index)]

func select_at(screen_point: Vector2) -> void:
	selected_index = signal_index_at(screen_point)
	_update_inspector()
	_redraw()

func signal_index_at(screen_point: Vector2) -> int:
	var index := -1
	var closest := 22.0
	for i in entries.size():
		var entry := entries[i]
		if section_index >= 0 and entry["section"] != get_current_section().id:
			continue
		var distance := cell_lane_to_screen(entry["cell"], entry["data"].lane).distance_to(screen_point)
		if distance < closest:
			closest = distance
			index = i
	return index

func measure_screen_point(screen_point: Vector2) -> void:
	var index := signal_index_at(screen_point)
	if index >= 0:
		var entry := entries[index]
		measure_at(Vector2(entry["cell"], entry["data"].lane))
	else:
		measure_at(screen_to_map(screen_point))

func measure_at(point: Vector2) -> void:
	if measurement.size() == 2:
		measurement.clear()
	measurement.append(point)
	coordinates.text = measurement_text()
	_redraw()

func measurement_text() -> String:
	if measurement.size() < 2:
		return "Shift-click two points to measure" if measurement.is_empty() else "RULER A: cell %.2f | lane %.2f. Shift-click B." % [measurement[0].x, measurement[0].y]
	var delta := measurement[1] - measurement[0]
	var direct := Vector2(delta.x, delta.y * facility_layout.lane_to_cell_scale).length()
	return "RULER  dx %.2f cells | dy %.2f lanes | direct %.2f cells" % [delta.x, delta.y, direct]

func _update_inspector() -> void:
	if selected_index < 0:
		inspector.text = "SIGNAL INSPECTOR\n\nClick a signal to inspect its authored placement.\n\nDistance grid: X = cells, Y = lanes.\n\nShift-click A and B to measure. Direct distance converts lanes using the gameplay metric; it is not route distance.\n\nDelete clears the ruler.\n\nPreview changes take effect in gameplay on the next run restart."
		return
	var entry := entries[selected_index]
	var data: SignalData = entry["data"]
	var text := "%s\n%s\n\nCell: %.2f\nLane: %d\nSection: %s\nFacing: %.1f deg\nHorizontal dx from frozen runner: %.2f cells" % [data.system_id, SignalData.Type.keys()[data.type], entry["cell"], data.lane, entry["section"], data.facing_deg, entry["cell"] - _runner_position.x]
	if data.detection != null:
		var d := data.detection
		text += "\n\nVISION\nLength: %.2f cells\nAngle: %.1f deg\nWatch offset: %.2f cells\nShape: %s" % [d.vision_length_cells, d.vision_angle_deg, d.watch_offset_cells, DetectionComponent.ShapeType.keys()[d.shape_type]]
		for point in d.patrol_points:
			text += "\nSweep: %.1f deg / %.1fs" % [point.facing_deg, point.dwell_sec]
	if data.mobility != null:
		text += "\n\nPATROL\nSpeed: %.2f cells/s\nMode: %s" % [data.mobility.move_speed_cells_per_sec, MobilityComponent.PatrolMode.keys()[data.mobility.patrol_mode]]
		for point in data.mobility.patrol_points:
			text += "\n(%.2f, %d) dwell %.1fs" % [point.cell_x, point.lane, point.dwell_sec]
	if data.ic_modules != null and not data.ic_modules.modules.is_empty():
		text += "\n\nIC"
		for module in data.ic_modules.modules:
			text += "\n" + module.get_script().resource_path.get_file().get_basename()
	inspector.text = text

func _redraw() -> void:
	if not is_node_ready() or facility_layout == null:
		return
	map_layer.preview_sections = visible_sections()
	map_layer.preview_signals = visible_entries()
	map_layer.draw_route = route_toggle.button_pressed
	map_layer.model_scale = zoom
	map_layer.queue_redraw()
	overlay.queue_redraw()
