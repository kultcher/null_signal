extends PanelContainer

# Decryption minigame. Player maps cipher letters to solution letters.

signal puzzle_solved
signal puzzle_failed

var linked_signal: ActiveSignal = null

var config := {
	"cipher": "ABCD",          # String or Array of cipher letters
	"mapping_offset": 5,       # Used if no explicit solution is provided
	"solution": [],            # Optional explicit solution array (same length as cipher)
	"keyspaces": [],           # Optional explicit keyspaces: Array[Array[String]]
	"keyspace_min": 3,
	"keyspace_max": 5,
	"cycle_interval": 0.08,    # Seconds between animation steps
	"cull_interval": 10.0,      # Seconds between culling cycles
	"base_cull_amount": 1,
	"focus_cull_bonus": 1,
	"guess_cull_bonus": 2,
	"boost_duration": 5.0,
	"boost_speed_mult": 1.66, # 66% faster
	"wrong_lockout_time": 2.0,
	"cell_width": 90,
	"cell_height": 140,
}

const COLOR_BG = Color.BLACK
const COLOR_TEXT = Color(0, 1, 0)
const COLOR_TEXT_DIM = Color(0, 1, 0, 0.55)
const COLOR_FOCUS = Color(1, 1, 0, 0.95)
const COLOR_ERROR = Color(1, 0.2, 0.2)

const DEBUG_DECRYPT = true

var cipher_chars: Array[String] = []
var solution_chars: Array[String] = []
var keyspaces: Array[PackedStringArray] = []

var cycle_indices: Array[int] = []
var confirmed: Array[bool] = []

var cipher_labels: Array[Label] = []
var input_edits: Array[LineEdit] = []
var keyspace_panels: Array[PanelContainer] = []
var anim_labels: Array[Label] = []
var set_labels: Array[Label] = []

var focused_index := -1

var cycle_timer: Timer
var cull_timer: Timer

var cull_footer: PanelContainer
var cull_progress: ProgressBar
var cull_label: Label

var suppress_input := false
var boost_time_left := 0.0
var cull_progress_style_normal: StyleBoxFlat
var cull_progress_style_boost: StyleBoxFlat

var null_spike_active: bool = false
func _ready():
	GlobalEvents.activate_null_spike.connect(activate_null_spike)
	GlobalEvents.deactivate_null_spike.connect(deactivate_null_spike)
	set_process_input(true)
	_apply_linked_puzzle_config()
	_build_ui()
	_init_puzzle()
	_start_timers()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("null_spike") and not event.is_echo():
		if not GlobalEvents.is_tutorial_feature_enabled("null_spike"):
			return
		if null_spike_active:
			GlobalEvents.deactivate_null_spike.emit()
		else:
			GlobalEvents.activate_null_spike.emit()
		get_viewport().set_input_as_handled()

func _apply_linked_puzzle_config() -> void:
	if linked_signal == null or linked_signal.data == null or linked_signal.data.puzzle == null:
		return

	var puzzle: PuzzleComponent = linked_signal.data.puzzle
	puzzle.ensure_puzzle_generated()
	if puzzle.puzzle_type != PuzzleComponent.Type.DECRYPT:
		return

	var decrypt_config := puzzle.get_decrypt_config()
	if decrypt_config == null:
		return

	match decrypt_config.cipher:
		DecryptPuzzleConfig.Cipher.REPLACEMENT:
			config.cipher = decrypt_config.cipher_text
			config.mapping_offset = decrypt_config.mapping_offset
			config.keyspace_min = decrypt_config.keyspace_min
			config.keyspace_max = decrypt_config.keyspace_max

func _build_ui():
	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	
	var bg = StyleBoxFlat.new()
	bg.bg_color = COLOR_BG
	add_theme_stylebox_override("panel", bg)
	
	var cipher_row = HBoxContainer.new()
	cipher_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cipher_row.add_theme_constant_override("separation", 10)
	root.add_child(cipher_row)
	
	var input_row = HBoxContainer.new()
	input_row.alignment = BoxContainer.ALIGNMENT_CENTER
	input_row.add_theme_constant_override("separation", 10)
	root.add_child(input_row)
	
	var keyspace_row = HBoxContainer.new()
	keyspace_row.alignment = BoxContainer.ALIGNMENT_CENTER
	keyspace_row.add_theme_constant_override("separation", 10)
	root.add_child(keyspace_row)
	
	_cipher_row = cipher_row
	_input_row = input_row
	_keyspace_row = keyspace_row
	
	_build_footer(root)

var _cipher_row: HBoxContainer
var _input_row: HBoxContainer
var _keyspace_row: HBoxContainer

func _init_puzzle():
	_clear_children(_cipher_row)
	_clear_children(_input_row)
	_clear_children(_keyspace_row)
	
	cipher_chars = _normalize_cipher(config.cipher)
	solution_chars = _build_solution(cipher_chars)
	keyspaces = _build_keyspaces(cipher_chars, solution_chars)
	
	cycle_indices.clear()
	confirmed.clear()
	cipher_labels.clear()
	input_edits.clear()
	keyspace_panels.clear()
	anim_labels.clear()
	set_labels.clear()
	
	for i in cipher_chars.size():
		cycle_indices.append(0)
		confirmed.append(false)
		
		var cipher_lbl = _make_cipher_label(cipher_chars[i])
		_cipher_row.add_child(cipher_lbl)
		cipher_labels.append(cipher_lbl)
		
		var input = _make_input_field(i)
		_input_row.add_child(input)
		input_edits.append(input)
		_apply_input_style_normal(i)
		
		var panel = _make_keyspace_panel(i)
		_keyspace_row.add_child(panel)
		keyspace_panels.append(panel)
		
	_update_all_keyspace_labels()
	_seed_anim_labels()
	_update_focus_visuals()

func _start_timers():
	cycle_timer = Timer.new()
	cycle_timer.wait_time = config.cycle_interval
	cycle_timer.autostart = true
	cycle_timer.one_shot = false
	cycle_timer.timeout.connect(_on_cycle_tick)
	add_child(cycle_timer)
	
	cull_timer = Timer.new()
	cull_timer.wait_time = config.cull_interval
	cull_timer.autostart = true
	cull_timer.one_shot = false
	cull_timer.timeout.connect(_on_cull_tick)
	add_child(cull_timer)
	
	_update_cull_ui()

func _make_cipher_label(text_value: String) -> Label:
	var lbl = Label.new()
	lbl.text = text_value
	lbl.custom_minimum_size = Vector2(config.cell_width, 30)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	return lbl

func _make_input_field(index: int) -> LineEdit:
	var input = LineEdit.new()
	input.custom_minimum_size = Vector2(config.cell_width, 34)
	input.max_length = 1
	input.placeholder_text = "?"
	input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.add_theme_font_size_override("font_size", 24)
	input.add_theme_color_override("font_color", COLOR_TEXT)
	input.add_theme_color_override("placeholder_color", COLOR_TEXT_DIM)
	input.text_changed.connect(_on_input_changed.bind(index))
	return input

func _make_keyspace_panel(index: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(config.cell_width, config.cell_height)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_keyspace_input.bind(index))
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05)
	style.border_color = Color(0, 1, 0, 0.35)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	
	var anim = Label.new()
	anim.custom_minimum_size = Vector2(config.cell_width, 36)
	anim.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	anim.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	anim.add_theme_font_size_override("font_size", 26)
	anim.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(anim)
	anim_labels.append(anim)
	
	var set_lbl = Label.new()
	set_lbl.custom_minimum_size = Vector2(config.cell_width, 40)
	set_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	set_lbl.add_theme_font_size_override("font_size", 16)
	set_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	vbox.add_child(set_lbl)
	set_labels.append(set_lbl)
	
	return panel

func _normalize_cipher(cipher_value) -> Array[String]:
	if cipher_value is String:
		var chars: Array[String] = []
		for c in cipher_value:
			chars.append(c)
		return chars
	if cipher_value is Array:
		return cipher_value.duplicate()
	return []

func _build_solution(cipher: Array[String]) -> Array[String]:
	if config.solution.size() == cipher.size():
		return config.solution.duplicate()
	
	var alphabet = _alphabet()
	var out: Array[String] = []
	for c in cipher:
		var idx = alphabet.find(c)
		if idx == -1:
			out.append(c)
		else:
			out.append(alphabet[(idx + int(config.mapping_offset)) % alphabet.size()])
	return out

func _build_keyspaces(cipher: Array[String], solution: Array[String]) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	if config.keyspaces.size() == cipher.size():
		for keyset in config.keyspaces:
			out.append(PackedStringArray(keyset))
		return out
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var alphabet = _alphabet()
	
	for i in cipher.size():
		var chars = rng.randi_range(config.keyspace_min, config.keyspace_max)
		var options: Array[String] = [solution[i]]
		while options.size() < chars:
			var pick = alphabet[rng.randi_range(0, alphabet.size() - 1)]
			if pick not in options:
				options.append(pick)
		options.shuffle()
		out.append(PackedStringArray(options))
	
	return out

func _alphabet() -> Array[String]:
	var letters: Array[String] = []
	for i in range(26):
		letters.append(String.chr(65 + i))
	return letters

func _on_cycle_tick():
	for i in keyspaces.size():
		if keyspaces[i].is_empty():
			continue
		cycle_indices[i] = (cycle_indices[i] + 1) % keyspaces[i].size()
		anim_labels[i].text = keyspaces[i][cycle_indices[i]]

func _on_cull_tick():
	for i in keyspaces.size():
		if confirmed[i]:
			continue
		var remove_count = int(config.base_cull_amount)
		if i == focused_index:
			remove_count += int(config.focus_cull_bonus)
		remove_count = max(remove_count, 0)
		_remove_wrong_options(i, remove_count)
	
	_update_all_keyspace_labels()
	_check_solution()
	_update_cull_ui()

func _remove_wrong_options(index: int, remove_count: int):
	if remove_count <= 0:
		return
	var options = keyspaces[index]
	if options.size() <= 1:
		return
	var solution = solution_chars[index]
	var removable: Array[String] = []
	for opt in options:
		if opt != solution:
			removable.append(opt)
	removable.shuffle()
	while remove_count > 0 and removable.size() > 0 and options.size() > 1:
		var removed = removable.pop_back()
		options.erase(removed)
		remove_count -= 1
	keyspaces[index] = options
	if options.size() == 1:
		_confirmed_collapse(index)

func _confirmed_collapse(index: int):
	if DEBUG_DECRYPT:
		print("DECRYPT CONFIRM index=%s cipher=%s solution=%s input=%s keyspace=%s" % [
			index,
			cipher_chars[index],
			solution_chars[index],
			input_edits[index].text,
			_format_set(keyspaces[index])
		])

	confirmed[index] = true
	keyspaces[index] = PackedStringArray([solution_chars[index]])
	cycle_indices[index] = 0
	anim_labels[index].text = solution_chars[index]
	set_labels[index].add_theme_color_override("font_color", COLOR_TEXT)
	_apply_input_style_correct(index)
	suppress_input = true
	input_edits[index].editable = false
	input_edits[index].text = solution_chars[index]
	suppress_input = false
	_update_all_keyspace_labels()

func _on_input_changed(text: String, index: int):
	if suppress_input or confirmed[index] or not input_edits[index].editable:
		return
	var clean = text.strip_edges().to_upper()
	if clean.length() > 1:
		clean = clean.substr(clean.length() - 1, 1)
	if input_edits[index].text != clean:
		input_edits[index].text = clean
	
	if clean == "":
		return
	
	if clean == solution_chars[index]:
		if DEBUG_DECRYPT:
			print("DECRYPT INPUT CORRECT index=%s cipher=%s input=%s keyspace=%s" % [
				index,
				cipher_chars[index],
				clean,
				_format_set(keyspaces[index])
			])

		_confirmed_collapse(index)
		_accelerate_next_cull()
		_check_solution()
	else:
		if DEBUG_DECRYPT:
			print("DECRYPT INPUT WRONG index=%s cipher=%s input=%s keyspace=%s" % [
				index,
				cipher_chars[index],
				clean,
				_format_set(keyspaces[index])
			])
		_handle_wrong_input(index, clean)

func _flash_input_error(index: int):
	var edit = input_edits[index]
	edit.add_theme_color_override("font_color", COLOR_ERROR)
	get_tree().create_timer(0.15, false).timeout.connect(
		func(): edit.add_theme_color_override("font_color", COLOR_TEXT)
	)

func _handle_wrong_input(index: int, guess: String):
	if linked_signal != null:
		GlobalEvents.telemetry_event.emit(linked_signal, "puzzle_input", {"puzzle": "decrypt", "ok": false, "index": index})
	var collapsed = false
	if guess != "":
		var options = keyspaces[index]
		if options.has(guess):
			options.erase(guess)
			keyspaces[index] = options
			if options.size() == 1 and options[0] == solution_chars[index]:
				collapsed = true
		_update_all_keyspace_labels()
	if collapsed:
		_lockout_then_confirm(index)
		return

	var edit = input_edits[index]
	edit.editable = false
	_apply_input_style_error(index)
	get_tree().create_timer(float(config.wrong_lockout_time), false).timeout.connect(
		func():
			edit.editable = true
			edit.text = ""
			_apply_input_style_normal(index)
	)

func _accelerate_next_cull():
	if cull_timer == null:
		return
	boost_time_left += float(config.boost_duration)
	_apply_boost_state(true)

func _on_keyspace_input(event: InputEvent, index: int):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if focused_index == index:
			focused_index = -1
		else:
			focused_index = index
		_update_focus_visuals()

func _update_focus_visuals():
	for i in keyspace_panels.size():
		var style = keyspace_panels[i].get_theme_stylebox("panel") as StyleBoxFlat
		if style == null:
			continue
		if i == focused_index:
			style.border_color = COLOR_FOCUS
			set_labels[i].add_theme_color_override("font_color", COLOR_FOCUS)
		else:
			style.border_color = Color(0, 1, 0, 0.35)
			if confirmed[i]:
				set_labels[i].add_theme_color_override("font_color", COLOR_TEXT)
			else:
				set_labels[i].add_theme_color_override("font_color", COLOR_TEXT_DIM)

func _update_all_keyspace_labels():
	for i in keyspaces.size():
		set_labels[i].text = _format_set(keyspaces[i])
		if confirmed[i]:
			set_labels[i].add_theme_color_override("font_color", COLOR_TEXT)
		elif i == focused_index:
			set_labels[i].add_theme_color_override("font_color", COLOR_FOCUS)
		else:
			set_labels[i].add_theme_color_override("font_color", COLOR_TEXT_DIM)

func _seed_anim_labels():
	for i in keyspaces.size():
		if keyspaces[i].is_empty():
			anim_labels[i].text = ""
		else:
			anim_labels[i].text = keyspaces[i][0]

func _format_set(options: PackedStringArray) -> String:
	return "{" + ", ".join(options) + "}"

func _check_solution():
	for i in solution_chars.size():
		if input_edits[i].text.to_upper() != solution_chars[i]:
			return
	cycle_timer.stop()
	cull_timer.stop()
	puzzle_solved.emit()

func _clear_children(container: Node):
	for child in container.get_children():
		child.queue_free()

func _build_footer(parent: VBoxContainer):
	cull_footer = PanelContainer.new()
	var footer_style = StyleBoxFlat.new()
	footer_style.bg_color = Color(0.05, 0.05, 0.05)
	footer_style.border_color = Color(0, 1, 0, 0.35)
	footer_style.border_width_top = 2
	cull_footer.add_theme_stylebox_override("panel", footer_style)
	parent.add_child(cull_footer)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	cull_footer.add_child(hbox)
	
	var label = Label.new()
	label.text = "CULL:"
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_font_size_override("font_size", 18)
	hbox.add_child(label)
	
	cull_progress = ProgressBar.new()
	cull_progress.custom_minimum_size = Vector2(220, 18)
	cull_progress.min_value = 0.0
	cull_progress.max_value = 1.0
	cull_progress.value = 0.0
	cull_progress_style_normal = StyleBoxFlat.new()
	cull_progress_style_normal.bg_color = Color(0, 1, 0, 0.8)
	cull_progress_style_boost = StyleBoxFlat.new()
	cull_progress_style_boost.bg_color = Color(1, 0.55, 0, 0.9)
	cull_progress.add_theme_stylebox_override("fill", cull_progress_style_normal)
	hbox.add_child(cull_progress)
	
	cull_label = Label.new()
	cull_label.text = "0.0s"
	cull_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	cull_label.add_theme_font_size_override("font_size", 16)
	hbox.add_child(cull_label)

func _update_cull_ui():
	if cull_timer == null:
		return
	var wait = max(cull_timer.wait_time, 0.001)
	var left = clamp(cull_timer.time_left, 0.0, wait)
	var progress = 1.0 - (left / wait)
	cull_progress.value = progress
	cull_label.text = "%.1fs" % left

func _process(delta: float):
	_update_boost_timer(delta)
	_update_cull_ui()

func _apply_input_style_normal(index: int):
	var edit = input_edits[index]
	edit.add_theme_color_override("font_color", COLOR_TEXT)
	edit.add_theme_color_override("font_color_read_only", COLOR_TEXT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05)
	style.border_color = Color(0, 1, 0, 0.35)
	style.set_border_width_all(2)
	edit.add_theme_stylebox_override("normal", style)
	edit.add_theme_stylebox_override("focus", style)
	edit.add_theme_stylebox_override("read_only", style)

func _apply_input_style_error(index: int):
	var edit = input_edits[index]
	edit.add_theme_color_override("font_uneditable_color", COLOR_ERROR)
	edit.add_theme_color_override("font_color_read_only", COLOR_ERROR)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.02, 0.02)
	style.border_color = COLOR_ERROR
	style.set_border_width_all(2)
	edit.add_theme_stylebox_override("normal", style)
	edit.add_theme_stylebox_override("focus", style)
	edit.add_theme_stylebox_override("read_only", style)

func _apply_input_style_correct(index: int):
	var edit = input_edits[index]
	edit.add_theme_color_override("font_uneditable_color", Color(0, 0, 0))
	edit.add_theme_color_override("font_color_read_only", Color(0, 0, 0))
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 1, 0)
	style.border_color = Color(0, 1, 0)
	style.set_border_width_all(2)
	edit.add_theme_stylebox_override("normal", style)
	edit.add_theme_stylebox_override("focus", style)
	edit.add_theme_stylebox_override("read_only", style)


func _update_boost_timer(delta: float):
	if boost_time_left <= 0.0:
		return
	boost_time_left = max(0.0, boost_time_left - delta)
	if boost_time_left == 0.0:
		_apply_boost_state(false)

func _apply_boost_state(is_boosted: bool):
	if cull_timer == null:
		return
	var target_wait = float(config.cull_interval)
	if is_boosted:
		target_wait = target_wait / float(config.boost_speed_mult)
	if cull_progress != null:
		if is_boosted:
			cull_progress.add_theme_stylebox_override("fill", cull_progress_style_boost)
		else:
			cull_progress.add_theme_stylebox_override("fill", cull_progress_style_normal)
	if abs(cull_timer.wait_time - target_wait) > 0.001:
		cull_timer.wait_time = target_wait
		# If we just boosted, make sure the next tick reflects the faster cadence.
		if is_boosted and cull_timer.time_left > target_wait:
			cull_timer.start(target_wait)

func _lockout_then_confirm(index: int):
	var edit = input_edits[index]
	edit.editable = false
	_apply_input_style_error(index)
	get_tree().create_timer(float(config.wrong_lockout_time), false).timeout.connect(
		func():
			if confirmed[index]:
				return
			_confirmed_collapse(index)
			_check_solution()
	)

# SIGNALLED FUNCTIONS

func activate_null_spike():
	null_spike_active = true
	
func deactivate_null_spike():
	null_spike_active = false
