# terminal_window.gd
# Terminal window UI. Sends commands to CommandDispatch for processing and displays result

# TODO: Add protection for session tabs of lost signals

extends PanelContainer

const MAGNIFYING_GLASS_ICON := preload("res://Visuals/Icons/Simple/magnifying-glass.svg")
const CHECK_MARK_ICON := preload("res://Visuals/Icons/Simple/check-mark.svg")
const PADLOCK_ICON := preload("res://Visuals/Icons/Simple/padlock.svg")
const PADLOCK_OPEN_ICON := preload("res://Visuals/Icons/Simple/padlock-open.svg")
const CANCEL_ICON := preload("res://Visuals/Icons/Simple/cancel.svg")
const SHIELD_ICON := preload("res://Visuals/Icons/Simple/shield.svg")

const CONNECTION_FLOW_TOTAL_DURATION := 0.96
const CONNECTION_FLOW_MAX_STEP_DELAY := 0.08

enum SessionVisualState { NONE, INACTIVE, ACTIVE }

signal session_opened(active_sig: ActiveSignal)
signal session_activated(active_sig: ActiveSignal)
signal session_deactivated(active_sig: ActiveSignal)
signal session_closed(active_sig: ActiveSignal)
signal session_line_display_mode_changed()
## Emitted after the Scan / Lock / IC detail panels refresh (the hardware deck mirrors them on its lamps).
signal detail_panel_refreshed()

@onready var command_line = $TerminalInner/TerminalVBox/CmdLineHBox/CommandLine
@onready var history = $TerminalInner/TerminalVBox/TerminalHistory
@onready var prefix = $TerminalInner/TerminalVBox/CmdLineHBox/InputPrefix
@onready var title_bar = $TerminalInner/TerminalVBox/TitleBar
@onready var title_text = $TerminalInner/TerminalVBox/TitleBar/TitleHBox/TitleText
@onready var session_tabs: TabBar = $TerminalInner/TerminalVBox/TitleBar/TitleHBox/SessionTabs
@onready var root_tab: TabBar = $TerminalInner/TerminalVBox/TitleBar/TitleHBox/RootTab

@onready var scan_panel = $TerminalInner/TerminalVBox/SignalDetailHBox/ScanPanel
@onready var scan_progress = $TerminalInner/TerminalVBox/SignalDetailHBox/ScanPanel/ScanProgress
@onready var scan_icon = $TerminalInner/TerminalVBox/SignalDetailHBox/ScanPanel/ScanProgress/ScanCenterBox/ScanHBox/ScanIcon
@onready var scan_label = $TerminalInner/TerminalVBox/SignalDetailHBox/ScanPanel/ScanProgress/ScanCenterBox/ScanHBox/ScanLabel

@onready var lock_panel = $TerminalInner/TerminalVBox/SignalDetailHBox/LockPanel
@onready var lock_icon = $TerminalInner/TerminalVBox/SignalDetailHBox/LockPanel/CenterContainer/LockHBox/LockIcon
@onready var lock_label = $TerminalInner/TerminalVBox/SignalDetailHBox/LockPanel/CenterContainer/LockHBox/LockLabel
@onready var toolbox_button = $TerminalInner/TerminalVBox/SignalDetailHBox/LockPanel/LockPanelButton
@onready var toolbox_panel = $TerminalInner/TerminalVBox/SignalDetailHBox/LockPanel/LockPanelButton/LockToolboxControl/ToolboxPanel

@onready var ic_panel = $TerminalInner/TerminalVBox/SignalDetailHBox/ICPanel
@onready var ic_progress = $TerminalInner/TerminalVBox/SignalDetailHBox/ICPanel/ICProgress
@onready var ic_icon = $TerminalInner/TerminalVBox/SignalDetailHBox/ICPanel/ICCenterBox/ICHBox/ICIcon
@onready var ic_label = $TerminalInner/TerminalVBox/SignalDetailHBox/ICPanel/ICCenterBox/ICHBox/ICLabel



@export var show_inactive_session_lines := true:
	set(value):
		if show_inactive_session_lines == value:
			return
		show_inactive_session_lines = value
		session_line_display_mode_changed.emit()

var active_signal: ActiveSignal		# assigned by window_manager
var active_session: TerminalSession
var root_signal: ActiveSignal
var root_session: TerminalSession

var _takeover_controller: TerminalTakeoverController
var _connection_flow_serial := 0
var _connection_send_locked := false
var _buffered_command_text := ""
var _buffered_command_signal: ActiveSignal = null
var _buffered_command_flow_serial := -1
var _scan_panel_tint: Color = Color.TRANSPARENT
var _lock_panel_tint: Color = Color.TRANSPARENT
var _ic_panel_tint: Color = Color.TRANSPARENT

func _ready():
	set_context()
	_focus_command_line()
	CommandDispatch.terminal_window = self
	CommandDispatch.command_complete.connect(_on_command_complete)
	CommandDispatch.command_error.connect(_on_command_error)
	GlobalEvents.signal_scanned.connect(_on_signal_scanned)
	GlobalEvents.signal_scan_complete.connect(_on_signal_scan_complete)
	GlobalEvents.puzzle_solved.connect(_on_signal_state_changed)
	GlobalEvents.puzzle_failed.connect(_on_signal_state_changed)
	root_session = TerminalSession.new()
	# Dummy signal for root session
	root_signal = ActiveSignal.new()
	active_signal = root_signal
	active_session = root_session
	root_session.has_tab = true
	root_session.active_signal = root_signal
	root_signal.terminal_session = root_session
	session_tabs.add_tab("root")
	_set_tab_session(0, root_session)
	_takeover_controller = TerminalTakeoverController.new(self, command_line, history, title_bar, title_text)
	_takeover_controller.set_session_context(active_session, root_signal)
	_refresh_prefix()
	_refresh_signal_detail_panel()

func _exit_tree() -> void:
	if root_signal != null:
		root_signal.release_run_state()

func _process(_delta: float) -> void:
	if active_signal != null and active_signal != root_signal:
		_refresh_signal_detail_panel()

func switch_session(new_sig: ActiveSignal, show_connection_banner: bool = false):
	if new_sig == null:
		print("null signal")
		return
	if active_signal == new_sig:
		_refresh_prefix()
		_focus_command_line()
		return

	# Create new session
	if new_sig.terminal_session == null:
		var new_session = TerminalSession.new()
		new_session.active_signal = new_sig
		new_session.has_tab = true
		new_sig.terminal_session = new_session
		ensure_tab_for_session(new_session)
		session_opened.emit(new_sig)
		_set_active_session(new_session)
		clear_log()
		if show_connection_banner:
			_play_connection_flow(new_sig)
		else:
			print_to_log("New session started with " + new_sig.data.system_id)
		print_to_root("<Session Log>: Connected to " + new_sig.data.system_id)
		_refresh_prefix()
		_focus_command_line()

	# Switch to existing session
	elif new_sig.terminal_session != null:
		var existing_session := new_sig.terminal_session
		if not existing_session.has_tab:
			ensure_tab_for_session(existing_session)
			session_opened.emit(new_sig)
		else:
			_select_tab_for_session(existing_session)
		_set_active_session(existing_session)
		if not active_session.has_tab:
			ensure_tab_for_session(active_session)
		if show_connection_banner:
			clear_log()
			active_session.history.clear()
			_play_connection_flow(new_sig)
			_refresh_prefix()
			_focus_command_line()
			return
		restore_session(active_session)

func failed_connection_feedback(active_sig):
	print_unlogged("<Session Log>: WARNING: " + active_sig.data.system_id + " out of range. Dropping to root.")
	if active_session != root_session:
		print_to_root("<Session Log>: WARNING: " + active_sig.data.system_id + " out of range. Dropping to root.")
	restore_session(root_session)

func access_signal_via_click(target_sig: ActiveSignal) -> void:
	if target_sig == null or target_sig.data == null:
		return
	var command_text := "ACC " + target_sig.data.system_id
	print_to_log("--[ " + command_text)
	CommandDispatch.process_command(command_text, active_signal)


func print_to_root(text: String):
	root_session.history.append(text)

func print_to_log(text: String):
	active_session.history.append(text)
	history.append_text(text + "\n")

func print_unlogged(text: String):
	history.append_text(text + "\n")

func print_transient(text: String) -> void:
	if text.is_empty():
		return
	print_unlogged(text)

func play_system_dump(text: String, initial_cps: float = 100.0, max_cps: float = 500.0) -> void:
	if _takeover_controller == null:
		return
	await _takeover_controller.play_system_dump(text, initial_cps, max_cps)

func estimate_type_duration(text: String, delay: float) -> float:
	if _takeover_controller == null:
		return 0.0
	return _takeover_controller.estimate_type_duration(text, delay)

func play_null_spike_sync(text: String, delay: float = 0.01) -> void:
	if _takeover_controller == null:
		return
	await _takeover_controller.play_null_spike_sync(text, delay)
	return

func clear_log():
	history.text = ""

func _print_connection_flow(target_sig: ActiveSignal) -> void:
	var lines := Jargonizer.build_connection_flow(target_sig)
	for line in lines:
		print_to_log(line)

func _play_connection_flow(target_sig: ActiveSignal) -> void:
	_connection_flow_serial += 1
	var flow_serial := _connection_flow_serial
	_connection_send_locked = true
	_clear_buffered_command()
	_stream_connection_flow_async(target_sig, flow_serial)

func _stream_connection_flow_async(target_sig: ActiveSignal, flow_serial: int) -> void:
	var lines := Jargonizer.build_connection_flow(target_sig)
	if lines.is_empty():
		_finish_connection_flow(flow_serial, target_sig)
		return

	var full_text := "\n".join(lines)
	var reveal_steps := _build_bbcode_safe_reveal_steps(full_text)
	var total_steps := reveal_steps.size()
	if total_steps <= 0:
		_finish_connection_flow(flow_serial, target_sig)
		return

	var char_delay := CONNECTION_FLOW_TOTAL_DURATION / float(total_steps)
	char_delay = minf(char_delay, CONNECTION_FLOW_MAX_STEP_DELAY)
	var base_text = history.text
	var reveal_progress: float = 0.0

	while reveal_progress < total_steps:
		if flow_serial != _connection_flow_serial:
			return
		if active_session == null or active_session.active_signal != target_sig:
			_finish_connection_flow(flow_serial, target_sig)
			return

		var delta := get_process_delta_time()
		var current_step := int(reveal_progress)
		var current_text := reveal_steps[current_step]
		var next_text := reveal_steps[min(current_step + 1, total_steps - 1)]
		if current_text.ends_with("\n") and current_text != next_text:
			reveal_progress += 1.0
			history.text = base_text + reveal_steps[min(int(reveal_progress), total_steps - 1)]
			await get_tree().create_timer(minf(0.02, maxf(0.001, char_delay * 2.0))).timeout
			continue

		reveal_progress += delta / maxf(0.001, char_delay)
		history.text = base_text + reveal_steps[min(int(reveal_progress), total_steps - 1)]
		await get_tree().process_frame

	if flow_serial == _connection_flow_serial:
		history.text = base_text + full_text + "\n"
		active_session.history.append_array(lines)
	_finish_connection_flow(flow_serial, target_sig)

func _build_bbcode_safe_reveal_steps(full_text: String) -> Array[String]:
	var steps: Array[String] = []
	var cursor := 0
	while cursor < full_text.length():
		if full_text[cursor] == "[":
			var closing_idx := full_text.find("]", cursor)
			if closing_idx != -1:
				var tag_end := closing_idx + 1
				var current_prefix := full_text.substr(0, tag_end)
				if steps.is_empty() or steps[-1] != current_prefix:
					steps.append(current_prefix)
				cursor = tag_end
				continue
		steps.append(full_text.substr(0, cursor + 1))
		cursor += 1
	return steps

func _finish_connection_flow(flow_serial: int, target_sig: ActiveSignal) -> void:
	if flow_serial != _connection_flow_serial:
		return
	_connection_send_locked = false
	_flush_buffered_command(target_sig, flow_serial)
	if target_sig != null and target_sig.data != null and target_sig.data.ic_modules != null:
		target_sig.data.ic_modules.notify_connected(target_sig)

func _clear_buffered_command() -> void:
	_buffered_command_text = ""
	_buffered_command_signal = null
	_buffered_command_flow_serial = -1

func _buffer_command_submit(new_text: String) -> void:
	_buffered_command_text = new_text
	_buffered_command_signal = active_signal
	_buffered_command_flow_serial = _connection_flow_serial
	command_line.clear()

func _flush_buffered_command(target_sig: ActiveSignal, flow_serial: int) -> void:
	if _buffered_command_text.is_empty():
		return
	if _buffered_command_signal != target_sig:
		_clear_buffered_command()
		return
	if _buffered_command_flow_serial != flow_serial:
		_clear_buffered_command()
		return

	var buffered_text := _buffered_command_text
	_clear_buffered_command()
	print_to_log("--[ " + buffered_text)
	CommandDispatch.process_command(buffered_text, active_signal)

func restore_session(session: TerminalSession):
	if active_session == null: return
	_set_active_session(session)
	if active_session.has_tab == false:
		ensure_tab_for_session(active_session)
	_select_tab_for_session(active_session)
	clear_log()
	for s in session.history:
		history.text += s + "\n"
	print_unlogged("---Reconnecting---\n")
	_refresh_prefix()
	_focus_command_line()
	_refresh_signal_detail_panel()

func set_context():	# add args later
	history.text = Jargonizer.get_handshake()
	for i in 3:
		await get_tree().create_timer(0.2).timeout
		history.text += "."
	history.text += "."
	await get_tree().create_timer(0.2).timeout
	history.text += "\nConnected."
	await get_tree().create_timer(0.2).timeout
	history.text += "\nEnter command.\n"

func _on_session_tabs_tab_clicked(tab: int) -> void:
	var session = _get_tab_session(tab)
	if session == active_session: return
	restore_session(session)

func _on_session_tabs_tab_close_pressed(tab: int) -> void:
	if tab == 0: return
	var session = _get_tab_session(tab)
	if session == null:
		return
	_close_session_tab(session, session.active_signal)

func hide_tab_for_signal(target_signal: ActiveSignal) -> void:
	if target_signal == null or target_signal.terminal_session == null:
		return
	var session := target_signal.terminal_session
	
	if not session.has_tab:
		return

	var tab_index := _find_tab_for_session(session)
	if tab_index == -1:
		_close_session_tab(session, target_signal)
		return

	if session == active_session:
		print_to_root("<Session Log>: WARNING: " + target_signal.data.system_id + " no longer in range. Dropping to root.")
	_close_session_tab(session, target_signal)
	return

func ensure_tab_for_session(session: TerminalSession):
	var existing_index = _find_tab_for_session(session)
	if existing_index != -1:
		session_tabs.current_tab = existing_index
		return
	var tab_label = "root"
	if session != root_session and session.active_signal != null:
		tab_label = session.active_signal.data.system_id
	session_tabs.add_tab(tab_label)
	var new_index = session_tabs.tab_count - 1
	_set_tab_session(new_index, session)
	session_tabs.current_tab = new_index
	session.has_tab = true

func _find_tab_for_session(session: TerminalSession) -> int:
	for i in range(session_tabs.tab_count):
		if _get_tab_session(i) == session:
			return i
	return -1

func _select_tab_for_session(session: TerminalSession) -> void:
	var tab_index := _find_tab_for_session(session)
	if tab_index != -1:
		session_tabs.current_tab = tab_index

func _get_tab_session(tab_index: int) -> TerminalSession:
	return session_tabs.get_tab_metadata(tab_index)

func _set_tab_session(tab_index: int, session: TerminalSession):
	session_tabs.set_tab_metadata(tab_index, session)

func get_session_visual_state(active_sig: ActiveSignal) -> int:
	if active_sig == null or active_sig == root_signal:
		return SessionVisualState.NONE
	if active_sig.terminal_session == null:
		return SessionVisualState.NONE

	var session := active_sig.terminal_session
	if not session.has_tab:
		return SessionVisualState.NONE
	if session == active_session:
		return SessionVisualState.ACTIVE
	return SessionVisualState.INACTIVE

func get_tab_anchor_global_position(session: TerminalSession) -> Vector2:
	if session == null:
		return Vector2(INF, INF)
	var tab_index := _find_tab_for_session(session)
	if tab_index == -1:
		return Vector2(INF, INF)
	var tab_rect = session_tabs.get_tab_rect(tab_index)
	var local_anchor = tab_rect.position + Vector2(tab_rect.size.x * 0.5, 0.0)
	return session_tabs.get_global_transform_with_canvas() * local_anchor

func _set_active_session(session: TerminalSession) -> void:
	var previous_session := active_session
	if previous_session == session:
		active_session = session
		active_signal = session.active_signal if session != null else root_signal
		if _takeover_controller != null:
			_takeover_controller.set_session_context(active_session, root_signal)
		_refresh_prefix()
		_refresh_signal_detail_panel()
		return

	active_session = session
	active_signal = session.active_signal if session != null else root_signal
	if _takeover_controller != null:
		_takeover_controller.set_session_context(active_session, root_signal)

	if previous_session != null and previous_session != root_session and previous_session.has_tab and previous_session.active_signal != null:
		session_deactivated.emit(previous_session.active_signal)

	if active_session != null and active_session != root_session and active_session.has_tab and active_session.active_signal != null:
		session_activated.emit(active_session.active_signal)
	_refresh_prefix()
	_refresh_signal_detail_panel()

func force_disconnect_signal(target_signal: ActiveSignal, reason_lines: Array[String] = []) -> void:
	if target_signal == null or target_signal.terminal_session == null:
		return

	var session := target_signal.terminal_session
	for line in reason_lines:
		if line.is_empty():
			continue
		session.history.append(line)
		if session == active_session:
			print_unlogged(line)
		print_to_root(line)

	if target_signal.data != null:
		print_to_root("<Session Log>: " + target_signal.data.system_id + " connection terminated.")

	if target_signal.instance_node != null and target_signal.instance_node.has_method("play_forced_disconnect_feedback"):
		await target_signal.instance_node.play_forced_disconnect_feedback()

	_close_session_tab(session, target_signal)

func _close_session_tab(session: TerminalSession, target_signal: ActiveSignal) -> void:
	if session == null:
		return

	var tab_index := _find_tab_for_session(session)
	if active_session == session:
		restore_session(root_session)

	session.has_tab = false
	if target_signal != null and target_signal.data != null and target_signal.data.ic_modules != null:
		target_signal.data.ic_modules.notify_session_closed(target_signal)
	if target_signal != null:
		session_closed.emit(target_signal)
	if tab_index != -1:
		session_tabs.remove_tab(tab_index)
	_refresh_signal_detail_panel()

# Signal Detail Panels

func _refresh_signal_detail_panel() -> void:
	if active_signal == null or active_signal == root_signal or active_signal.data == null:
		_apply_default_detail_panel_state()
		detail_panel_refreshed.emit()
		return

	_refresh_scan_panel(active_signal)
	_refresh_lock_panel(active_signal)
	_refresh_ic_panel(active_signal)
	detail_panel_refreshed.emit()

func _apply_default_detail_panel_state() -> void:
	scan_progress.max_value = 1.0
	scan_progress.value = 0.0
	scan_progress.self_modulate = ActiveSignal.COLOR_STATUS_UNKNOWN
	scan_icon.texture = MAGNIFYING_GLASS_ICON
	scan_icon.self_modulate = ActiveSignal.COLOR_STATUS_UNKNOWN
	scan_label.text = "Scan: Unscanned"
	scan_label.self_modulate = ActiveSignal.COLOR_STATUS_UNKNOWN
	_apply_panel_tint(scan_panel, ActiveSignal.COLOR_STATUS_UNKNOWN, "_scan_panel_tint")

	lock_icon.texture = PADLOCK_ICON
	lock_icon.self_modulate = ActiveSignal.COLOR_STATUS_UNKNOWN
	lock_label.text = "Lock: Unverified"
	lock_label.self_modulate = ActiveSignal.COLOR_STATUS_UNKNOWN
	_apply_panel_tint(lock_panel, ActiveSignal.COLOR_STATUS_UNKNOWN, "_lock_panel_tint")

	ic_progress.max_value = 1.0
	ic_progress.value = 0.0
	ic_progress.self_modulate = ActiveSignal.COLOR_STATUS_UNKNOWN
	ic_icon.texture = SHIELD_ICON
	ic_icon.self_modulate = ActiveSignal.COLOR_STATUS_UNKNOWN
	ic_label.text = "IC: Unknown"
	ic_label.self_modulate = ActiveSignal.COLOR_STATUS_UNKNOWN
	_apply_panel_tint(ic_panel, ActiveSignal.COLOR_STATUS_UNKNOWN, "_ic_panel_tint")

func _refresh_scan_panel(target_sig: ActiveSignal) -> void:
	var total_layers = max(1, target_sig.get_total_scan_layer_count())
	var revealed_layers := target_sig.get_revealed_scan_layer_count()
	var display_value := float(revealed_layers)
	if target_sig.is_being_scanned and target_sig.current_scan_index < target_sig.scan_layers.size():
		var current_layer = target_sig.scan_layers[target_sig.current_scan_index]
		var current_fraction := 0.0
		if current_layer.duration > 0.0:
			current_fraction = clampf(target_sig.current_layer_progress / current_layer.duration, 0.0, 1.0)
		display_value = minf(float(total_layers), float(revealed_layers) + current_fraction)

	var scan_color := target_sig.get_scan_status_color()
	scan_progress.max_value = total_layers
	scan_progress.value = display_value
	scan_progress.self_modulate = scan_color
	scan_icon.texture = CHECK_MARK_ICON if target_sig.get_scan_status_icon_state() == ActiveSignal.TooltipIconState.COMPLETE else MAGNIFYING_GLASS_ICON
	scan_icon.self_modulate = scan_color
	scan_label.text = target_sig.get_scan_status_label_text()
	scan_label.self_modulate = scan_color
	_apply_panel_tint(scan_panel, scan_color, "_scan_panel_tint")

func _refresh_lock_panel(target_sig: ActiveSignal) -> void:
	var lock_state := target_sig.get_lock_status_icon_state()
	var lock_color := target_sig.get_lock_status_color()
	match lock_state:
		ActiveSignal.TooltipIconState.UNKNOWN_LOCK:
			toolbox_button.disabled = true
			return
		ActiveSignal.TooltipIconState.OPEN, ActiveSignal.TooltipIconState.HACKED:
			lock_icon.texture = PADLOCK_OPEN_ICON
			toolbox_button.disabled = true
		_:
			lock_icon.texture = PADLOCK_ICON
			toolbox_button.disabled = false
	lock_icon.self_modulate = lock_color
	lock_label.text = target_sig.get_lock_status_label_text()
	lock_label.self_modulate = lock_color
	_apply_panel_tint(lock_panel, lock_color, "_lock_panel_tint")

func _refresh_ic_panel(target_sig: ActiveSignal) -> void:
	var ic_state := target_sig.get_ic_status_icon_state()
	var ic_color := target_sig.get_ic_status_color()
	var ic_progress_color := target_sig.get_ic_progress_color()
	match ic_state:
		ActiveSignal.TooltipIconState.NO_IC:
			ic_icon.texture = CANCEL_ICON
		ActiveSignal.TooltipIconState.ACTIVE_IC:
			ic_icon.texture = SHIELD_ICON
		_:
			ic_icon.texture = SHIELD_ICON
	ic_progress.max_value = target_sig.get_ic_scan_progress_max()
	ic_progress.value = target_sig.get_ic_scan_progress_value()
	ic_progress.self_modulate = ic_progress_color
	ic_icon.self_modulate = ic_color
	ic_label.text = target_sig.get_ic_status_detail_text()
	ic_label.self_modulate = ic_color
	_apply_panel_tint(ic_panel, ic_color, "_ic_panel_tint")

func _apply_panel_tint(panel: PanelContainer, accent: Color, cache_field: String) -> void:
	if panel == null:
		return
	if get(cache_field) == accent:
		return
	var base_style := panel.get_theme_stylebox("panel")
	if not (base_style is StyleBoxFlat):
		return
	var style := (base_style as StyleBoxFlat).duplicate()
	style.bg_color = Color(
		clampf(accent.r * 0.18, 0.05, 1.0),
		clampf(accent.g * 0.18, 0.05, 1.0),
		clampf(accent.b * 0.18, 0.05, 1.0),
		1.0
	)
	style.border_color = accent
	panel.add_theme_stylebox_override("panel", style)
	set(cache_field, accent)

func _on_signal_scanned(signal_data: SignalData, _scan_depth) -> void:
	if active_signal == null or active_signal == root_signal or signal_data != active_signal.data:
		return
	_refresh_signal_detail_panel()

func _on_signal_scan_complete(signal_data: SignalData) -> void:
	#NOTE: This could be more robust
	if signal_data.ic_modules:
		for ic in signal_data.ic_modules.modules:
			print_transient("[color=red]WARNING[/color]: [color=cyan]IC detected[/color] on " + signal_data.display_name + ": " + ic.warning_notice())
	if active_signal == null or active_signal == root_signal or signal_data != active_signal.data:
		return
	_refresh_signal_detail_panel()

func _on_signal_state_changed(signal_data) -> void:
	if active_signal == null or active_signal == root_signal or signal_data != active_signal.data:
		return
	_refresh_signal_detail_panel()

# SIGNALLED FUNCTIONS

func _on_command_line_text_submitted(new_text: String) -> void:
	if _connection_send_locked:
		_buffer_command_submit(new_text)
		return
	print_to_log("--[ " + new_text)
	CommandDispatch.process_command(new_text, active_signal)
	command_line.clear()

func _on_command_complete(cmd_context: CommandContext) -> void:
	if cmd_context.active_sig != active_signal:		# ensure command signaldata matches terminal signaldata
		return
	for s in cmd_context.log_text:
		print_to_log(s)

func _on_command_error(error_msg: String, signal_context: ActiveSignal = null) -> void:
	if signal_context != active_signal:
		return
	print_to_log("!! ERROR: " + error_msg)

func _refresh_prefix() -> void:
	if prefix == null:
		return
	if active_session == null or active_signal == null or active_signal == root_signal:
		prefix.text = "- root -["
		prefix.remove_theme_color_override("font_color")
		return
	prefix.text = "-" + active_signal.data.system_id + "-["
	if active_signal.data != null and active_signal.data.visuals != null:
		prefix.add_theme_color_override("font_color", active_signal.data.visuals.fill_color)
	else:
		prefix.remove_theme_color_override("font_color")

func _focus_command_line() -> void:
	if command_line == null:
		return
	command_line.grab_focus()
	command_line.caret_column = command_line.text.length()

#####	
# TOOLBOX stuff	
#####

var toolbox_open: bool = false

func _on_lock_center_box_pressed() -> void:
	_toggle_toolbox()

func _toggle_toolbox():
	if !toolbox_open:
		_open_toolbox()
	else:
		_close_toolbox()
	
func _open_toolbox():
	var panel_shift = toolbox_panel.position.y + toolbox_panel.size.y
	var tween = create_tween()
	toolbox_panel.z_index = 0
	toolbox_panel.show()
	toolbox_open = true
	tween.tween_property(toolbox_panel, "position:y", -panel_shift, .1)
	await tween.finished
	tween.kill()

func _close_toolbox():
	var panel_shift = toolbox_panel.position.y + toolbox_panel.size.y
	var tween = create_tween()
	toolbox_panel.z_index = 0
	tween.tween_property(toolbox_panel, "position:y", panel_shift, .1)
	await tween.finished
	tween.kill()
	toolbox_panel.z_index = -20
	toolbox_panel.hide()
	toolbox_open = false

func _on_sniff_button_pressed() -> void:
	command_line.grab_focus()
	command_line.text = "RUN sniff"
	_on_command_line_text_submitted(command_line.text)
	_close_toolbox()

func _on_decrypt_button_pressed() -> void:
	command_line.grab_focus()
	command_line.text = "RUN decrypt"
	_on_command_line_text_submitted(command_line.text)
	_close_toolbox()
