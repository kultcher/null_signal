class_name SessionDisruptionController extends Node
## One owner for input queues and shared-screen effects, independent of signal
## visuals (which may despawn). Open background sessions remain alive.

signal effect_event(sig: ActiveSignal, effect: StringName, event: StringName, details: Dictionary)

var terminal: Control
var sessions: Dictionary = {}
var clock := 0.0
var presentation_suspended := false
var overlay_layer: CanvasLayer
var input_overlay: DegradedInputOverlay
var _drafts: Dictionary = {}
var _refresh_age := 0.0
# Last disruption visuals pushed per signal instance, so entities are only
# touched when their state changes (and not at all while nothing is active).
var _applied_visuals: Dictionary = {}
const _NO_STATE := {"modules": {}}
const _NO_VISUALS := [Vector2.ZERO, false, false, false, false]

func initialize(target: Control) -> void:
	terminal = target
	terminal.session_opened.connect(open_session)
	terminal.session_closed.connect(close_session)
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 15
	add_child(overlay_layer)
	input_overlay = DegradedInputOverlay.new()
	terminal.command_line.add_child(input_overlay)
	input_overlay.initialize(terminal.command_line)
	terminal.command_line.gui_input.connect(_input_field_mouse)
	set_process_input(true)

func open_session(sig: ActiveSignal) -> void:
	if sig == null or sig.data == null or sig.is_disabled or sessions.has(sig.get_instance_id()):
		return
	if sig.terminal_session == null or not sig.terminal_session.has_tab:
		return
	var modules: Dictionary = {}
	if sig.data.ic_modules != null:
		for module in sig.data.ic_modules.modules:
			if module is DisruptionModule:
				modules[module.get_effect_id()] = module
	if modules.is_empty():
		return
	var state := {"sig": sig, "modules": modules, "age": 0.0, "seed": randi(), "queue": [], "popups": [], "spawn_age": 0.0, "editor": null, "viewport": null}
	sessions[sig.get_instance_id()] = state
	if modules.has(&"lag"):
		_create_editor(state)
	for key in modules:
		effect_event.emit(sig, key, &"started", {})
	# Apply Blackout / Glitch / Redact visuals now rather than next frame.
	_update_signal_visuals()

func close_session(sig: ActiveSignal) -> void:
	if sig == null:
		return
	var state: Dictionary = sessions.get(sig.get_instance_id(), {})
	if state.is_empty():
		return
	for popup in state.popups:
		if is_instance_valid(popup):
			popup.queue_free()
	if is_instance_valid(state.viewport):
		state.viewport.queue_free()
	for key in state.modules:
		effect_event.emit(sig, key, &"ended", {})
	sessions.erase(sig.get_instance_id())
	if sig.terminal_session != null:
		_drafts.erase(sig.terminal_session.get_instance_id())
	# Restore visuals (and un-redacted tooltip text) immediately.
	_update_signal_visuals()
	_update_signal_visuals()
	if terminal.active_signal == sig and not presentation_suspended:
		terminal._set_history_text(terminal._history_source)
	_render_terminal()

func activate_session(previous: TerminalSession, current: TerminalSession) -> void:
	var line: LineEdit = terminal.command_line
	if previous != null:
		var previous_id := previous.get_instance_id()
		_drafts[previous_id] = {"text": line.text, "caret": line.caret_column}
	var state := _state(current.active_signal if current != null else null)
	if state.has("editor") and state.editor != null:
		_mirror_editor(state)
	else:
		var draft: Dictionary = _drafts.get(current.get_instance_id(), {}) if current != null else {}
		line.text = draft.get("text", "")
		line.caret_column = int(draft.get("caret", line.text.length()))
	input_overlay.restore()

func _create_editor(state: Dictionary) -> void:
	# Replay into an isolated native LineEdit. This preserves Godot's complete
	# editing behavior rather than implementing a partial keyboard editor.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1200, 64)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.handle_input_locally = true
	add_child(viewport)
	var editor := LineEdit.new()
	editor.size = Vector2(1200, 64)
	editor.keep_editing_on_text_submit = true
	editor.deselect_on_focus_loss_enabled = false
	editor.virtual_keyboard_enabled = false
	viewport.add_child(editor)
	editor.grab_focus()
	editor.edit()
	editor.text_submitted.connect(func(text: String):
		var sig: ActiveSignal = state.sig
		if sessions.has(sig.get_instance_id()) and sig.terminal_session != null and sig.terminal_session.has_tab:
			effect_event.emit(sig, &"lag", &"submitted", {"delay_sec": state.modules[&"lag"].delay_sec})
			terminal.submit_for_signal(text, sig)
		editor.clear()
	)
	state.editor = editor
	state.viewport = viewport

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or presentation_suspended or not terminal.command_line.has_focus() or not terminal.command_line.editable:
		return
	var state := _state(terminal.active_signal)
	if not state.modules.has(&"lag"):
		return
	queue_input(terminal.active_signal, event)
	get_viewport().set_input_as_handled()

func _input_field_mouse(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_sync_mouse_selection.call_deferred(terminal.active_signal)

func _sync_mouse_selection(sig: ActiveSignal) -> void:
	var state := _state(sig)
	if terminal.active_signal != sig or not state.modules.has(&"lag"):
		return
	var line: LineEdit = terminal.command_line
	state.editor.caret_column = line.caret_column
	if line.has_selection():
		state.editor.select(line.get_selection_from_column(), line.get_selection_to_column())
	else:
		state.editor.deselect()

func clear_input_draft(sig: ActiveSignal) -> void:
	var state := _state(sig)
	if state.modules.has(&"lag"):
		state.queue.clear()
		state.editor.clear()

func queue_input(sig: ActiveSignal, event: InputEventKey) -> void:
	var state := _state(sig)
	if not state.modules.has(&"lag"):
		return
	var delay := maxf(0.0, state.modules[&"lag"].delay_sec)
	# Nondecreasing due times retain ordering if tuning changes mid-stream.
	var due := clock + delay
	if not state.queue.is_empty():
		due = maxf(due, state.queue[-1].due)
	state.queue.append({"due": due, "event": event.duplicate()})
	if event.pressed:
		effect_event.emit(sig, &"lag", &"queued", {"delay_sec": delay, "pending": state.queue.size()})

func _process(delta: float) -> void:
	clock += delta
	for state in sessions.values():
		var sig: ActiveSignal = state.sig
		if sig.is_disabled or sig.terminal_session == null or not sig.terminal_session.has_tab:
			close_session(sig)
			continue
		state.age += delta
		if not presentation_suspended:
			_deliver_input(state)
		if state.modules.has(&"spammer"):
			_tick_spammer(state, delta)
	_update_signal_visuals()
	_refresh_age += delta
	if _refresh_age >= 0.1:
		_refresh_age = 0.0
		_render_terminal()

func _deliver_input(state: Dictionary) -> void:
	if state.editor == null:
		return
	# The connection banner has its own send lock. Keep every queued Enter
	# instead of replacing the banner's single buffered-command slot.
	if terminal.is_connection_pending(state.sig):
		return
	if state.queue.is_empty() or state.queue[0].due > clock:
		return
	var previous_focus: Control = terminal.get_viewport().gui_get_focus_owner()
	var previous_deselect := true
	if previous_focus is LineEdit:
		previous_deselect = previous_focus.deselect_on_focus_loss_enabled
		previous_focus.deselect_on_focus_loss_enabled = false
	# Godot shares focus between a parent viewport and its subviewports. Borrow
	# it only during synchronous replay, then restore the player's UI focus.
	state.editor.grab_focus()
	state.editor.edit()
	var changed := false
	while not state.queue.is_empty() and state.queue[0].due <= clock:
		var item: Dictionary = state.queue.pop_front()
		state.viewport.push_input(item.event, true)
		changed = true
		if not sessions.has(state.sig.get_instance_id()):
			_restore_focus(previous_focus, previous_deselect)
			return
	_restore_focus(previous_focus, previous_deselect)
	if changed and terminal.active_signal == state.sig:
		_mirror_editor(state)

func _restore_focus(previous: Control, deselect: bool) -> void:
	if not is_instance_valid(previous):
		return
	previous.grab_focus()
	if previous is LineEdit:
		previous.deselect_on_focus_loss_enabled = deselect

func _mirror_editor(state: Dictionary) -> void:
	var line: LineEdit = terminal.command_line
	var editor: LineEdit = state.editor
	line.text = editor.text
	line.caret_column = editor.caret_column
	if editor.has_selection():
		line.select(editor.get_selection_from_column(), editor.get_selection_to_column())
	else:
		line.deselect()

func _state(sig: ActiveSignal) -> Dictionary:
	# Shared read-only default: callers only write to real session states.
	return sessions.get(sig.get_instance_id(), _NO_STATE) if sig != null else _NO_STATE

func has_effect(sig: ActiveSignal, key: StringName) -> bool:
	return _state(sig).modules.has(key)

func is_blacked_out() -> bool:
	for state in sessions.values():
		if state.modules.has(&"blackout"):
			return true
	return false

func glitch_phase(sig: ActiveSignal) -> int:
	var state := _state(sig)
	if not state.modules.has(&"glitch"):
		return 0
	var module: GlitchModule = state.modules[&"glitch"]
	return int(state.age / maxf(0.1, module.jump_interval_sec)) % clampi(module.position_count, 2, 12)

func glitch_offset(sig: ActiveSignal) -> Vector2:
	var phase := glitch_phase(sig)
	if phase == 0:
		return Vector2.ZERO
	var module: GlitchModule = _state(sig).modules[&"glitch"]
	var angle := TAU * float(phase - 1) / float(clampi(module.position_count, 2, 12) - 1)
	return Vector2(cos(angle) * maxf(32.0, absf(module.max_offset_px.x)), sin(angle) * maxf(32.0, absf(module.max_offset_px.y)))

func fake_clicked(sig: ActiveSignal, position: Vector2) -> void:
	var manager = CommandDispatch.signal_manager
	if manager != null:
		var ripple := GlitchRipple.new()
		manager.add_child(ripple)
		ripple.global_position = position
		ripple.z_index = 50
	effect_event.emit(sig, &"glitch", &"fake_clicked", {"phase": glitch_phase(sig)})

func _update_signal_visuals() -> void:
	var manager = CommandDispatch.signal_manager
	if manager == null:
		return
	if sessions.is_empty() and _applied_visuals.is_empty():
		return
	var blackout := is_blacked_out()
	var seen := {}
	for sig in manager.signal_queue:
		if sig.instance_node == null or not is_instance_valid(sig.instance_node):
			continue
		var node_id: int = sig.instance_node.get_instance_id()
		seen[node_id] = true
		# Redact is included so the tooltip text re-renders when it starts/ends.
		var wanted := [glitch_offset(sig), has_effect(sig, &"glitch"), glitch_phase(sig) != 0, blackout, has_effect(sig, &"redact")]
		if wanted == _applied_visuals.get(node_id, _NO_VISUALS):
			continue
		sig.instance_node.apply_disruption_visuals(wanted[0], wanted[1], wanted[2], wanted[3])
		if wanted == _NO_VISUALS:
			_applied_visuals.erase(node_id)
		else:
			_applied_visuals[node_id] = wanted
	for node_id in _applied_visuals.keys():
		if not seen.has(node_id):
			_applied_visuals.erase(node_id)

func security_text(sig: ActiveSignal, source: String) -> String:
	var state := _state(sig)
	if not state.modules.has(&"redact"):
		return source
	return DisruptionText.transform(source, state.modules[&"redact"].letter_fraction, int(state.seed), true, 0, _callback_tokens(sig))

func _callback_tokens(sig: ActiveSignal) -> Array[String]:
	var protected_strings: Array[String] = []
	if sig == null or sig.data == null or sig.data.ic_modules == null:
		return protected_strings
	for module in sig.data.ic_modules.modules:
		if module is CallbackModule and not module.callback_sequence.is_empty():
			protected_strings.append("$" + module.callback_sequence)
	return protected_strings

func degraded_text(sig: ActiveSignal, source: String, protect_challenge := true) -> String:
	var state := _state(sig)
	if not state.modules.has(&"degrade"):
		return source
	var module: DegradeModule = state.modules[&"degrade"]
	var fraction := clampf(state.age / maxf(0.1, module.ramp_sec), 0.0, 1.0) * clampf(module.max_corruption, 0.0, 1.0)
	var tokens: Array[String] = []
	if protect_challenge:
		tokens = _callback_tokens(sig)
	return DisruptionText.transform(source, fraction, int(state.seed), false, int(state.age / maxf(0.05, module.noise_interval_sec)), tokens)

func terminal_text(sig: ActiveSignal, source: String) -> String:
	var state := _state(sig)
	if not state.modules.has(&"redact") and not state.modules.has(&"degrade"):
		return source
	var result := ""
	# User command echoes are not security prompts. Their actual value remains
	# readable under Redact; Degrade can still visually corrupt them.
	for line in source.split("\n"):
		result += (line if line.begins_with("--[ ") else security_text(sig, line)) + "\n"
	result = result.trim_suffix("\n")
	return degraded_text(sig, result)

func _render_terminal() -> void:
	if presentation_suspended or terminal.active_signal == null:
		return
	var state := _state(terminal.active_signal)
	if not state.modules.has(&"redact") and not state.modules.has(&"degrade"):
		input_overlay.restore()
		return
	var displayed := terminal_text(terminal.active_signal, terminal._history_source)
	if terminal.history.text != displayed:
		var scroll: VScrollBar = terminal.history.get_v_scroll_bar()
		var old_value := scroll.value
		var following := old_value >= scroll.max_value - scroll.page - 2.0
		terminal.history.text = displayed
		if not following:
			scroll.set_deferred("value", old_value)
	if state.modules.has(&"degrade") and not terminal.command_line.text.is_empty():
		# Redact censors prompts, not the player's input. Degrade may obscure
		# input, but the output challenge itself must remain readable.
		var displayed_input := degraded_text(terminal.active_signal, terminal.command_line.text, false)
		input_overlay.show_noise(displayed_input)
	else:
		input_overlay.restore()

func _tick_spammer(state: Dictionary, delta: float) -> void:
	var module: SpammerModule = state.modules[&"spammer"]
	state.spawn_age += delta
	if state.spawn_age < maxf(0.1, module.spawn_interval_sec):
		return
	state.spawn_age = 0.0
	for i in range(state.popups.size() - 1, -1, -1):
		if not is_instance_valid(state.popups[i]) or state.popups[i].is_queued_for_deletion():
			state.popups.remove_at(i)
	if state.popups.size() >= clampi(module.max_popups, 1, 20):
		return
	_spawn_popup(state, module)

func _spawn_popup(state: Dictionary, module: SpammerModule) -> void:
	var rect := _popup_region(module.placement)
	var popup := PanelContainer.new()
	popup.name = "SpamPopup"
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.modulate.a = 0.0
	var theme := Theme.new()
	theme.default_font = terminal.command_line.get_theme_font("font")
	theme.default_font_size = 18
	popup.theme = theme
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.018, 0.045, 0.98)
	style.border_color = Color(1.0, 0.35, 0.55)
	style.set_border_width_all(2)
	style.set_content_margin_all(12)
	popup.add_theme_stylebox_override("panel", style)
	overlay_layer.add_child(popup)
	var rows := VBoxContainer.new()
	popup.add_child(rows)
	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := Label.new()
	title.text = "UNSOLICITED // " + state.sig.data.system_id
	title.clip_text = true
	title.custom_minimum_size.x = 180
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	header.add_child(close)
	close.pressed.connect(func():
		popup.queue_free()
		effect_event.emit(state.sig, &"spammer", &"dismissed", {})
	)
	var message := Label.new()
	message.text = ["YOUR CHANNEL IS IMPORTANT TO US", "CLICK LESS. CONNECT MORE.", "MANDATORY OPTIONAL SECURITY UPDATE", "UPGRADE YOUR INTRUSION EXPERIENCE"][randi_range(0, 3)]
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(message)
	var footer := Label.new()
	footer.text = "Disconnect host to unsubscribe."
	rows.add_child(footer)
	popup.custom_minimum_size = Vector2(minf(maxf(220, module.popup_size.x), rect.size.x), minf(maxf(120, module.popup_size.y), rect.size.y))
	popup.size = popup.custom_minimum_size
	popup.position = rect.position + Vector2(randf() * maxf(0, rect.size.x - popup.size.x), randf() * maxf(0, rect.size.y - popup.size.y))
	state.popups.append(popup)
	effect_event.emit(state.sig, &"spammer", &"spawned", {"count": state.popups.size(), "placement": module.placement})
	# Wrapped labels initially measure before their container has a width.
	# Refit after layout so that provisional text height cannot enlarge a popup
	# past its region (and so different fonts/window sizes remain supported).
	await get_tree().process_frame
	if is_instance_valid(popup) and not popup.is_queued_for_deletion():
		popup.size = popup.custom_minimum_size
		popup.position.x = clampf(popup.position.x, rect.position.x, maxf(rect.position.x, rect.end.x - popup.size.x))
		popup.position.y = clampf(popup.position.y, rect.position.y, maxf(rect.position.y, rect.end.y - popup.size.y))
		popup.modulate.a = 1.0

func _popup_region(placement: int) -> Rect2:
	if placement == SpammerModule.Placement.BOTH:
		placement = randi_range(0, 1)
	if placement == SpammerModule.Placement.TERMINAL:
		return terminal.get_global_rect()
	var timeline = CommandDispatch.timeline_manager
	if timeline != null:
		return Rect2(timeline.get_global_transform_with_canvas().origin, Vector2(timeline.screen_width, timeline.map_height_px))
	return Rect2(Vector2.ZERO, Vector2(1000, 450))

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if input_overlay != null and is_instance_valid(input_overlay):
			input_overlay.restore()
		sessions.clear()
