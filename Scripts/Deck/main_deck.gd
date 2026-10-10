# main_deck.gd
# The player's deck: wide terminal screen plus the physical indicators around it.
# All indicator positions come from the Blender metadata (deck_main.json), so the
# lamps / gauges always sit exactly on the rendered hardware.

class_name MainDeck
extends DeviceShell

signal cartridge_pressed(index: int)
signal lamp_pressed(key: String)
## button: MOUSE_BUTTON_LEFT / MOUSE_BUTTON_RIGHT
signal program_cartridge_pressed(program_id: StringName, button: int)

## Program states as plain ints (same order as ProgramInstance.State).
enum ProgState { DOCKED, LOADING, RUNNING, CLEANUP }
const CART_TINTS := [Color(0.95, 0.55, 0.25), Color(0.55, 0.8, 0.95), Color(0.88, 0.86, 0.78), Color(0.65, 0.8, 0.45)]
const PROG_COLORS := {1: Color(1.0, 0.7, 0.2), 2: Color(0.3, 1.0, 0.5), 3: Color(1.0, 0.3, 0.45)}

enum Lamp { OFF, IDLE, ACTIVE, WARN, ALERT }

const FONT := preload("res://Visuals/Fonts/KodeMono-Bold.ttf")
const LAMP_KEYS := ["lamp_scan", "lamp_lock", "lamp_ic", "lamp_aux"]
const LAMP_DEFAULT_TEXT := {"lamp_scan": "SCAN", "lamp_lock": "LOCK", "lamp_ic": "IC", "lamp_aux": "AUX"}
const LAMP_COLORS := {
	Lamp.OFF: Color(0.10, 0.22, 0.14, 0.0),
	Lamp.IDLE: Color(0.15, 0.45, 0.25, 0.03),
	Lamp.ACTIVE: Color(0.25, 1.00, 0.55, 0.10),
	Lamp.WARN: Color(1.00, 0.70, 0.10, 0.12),
	Lamp.ALERT: Color(1.00, 0.18, 0.12, 0.16),
}
const PHOSPHOR := Color(0.55, 1.0, 0.7)
## Light energy each lamp state throws onto the surrounding hardware.
const LAMP_LIGHT_ENERGY := {Lamp.OFF: 0.0, Lamp.IDLE: 0.25, Lamp.ACTIVE: 2.0, Lamp.WARN: 2.0, Lamp.ALERT: 2.6}
const AMBER := Color(1.0, 0.72, 0.3)
const DECAL_DIR := "res://Visuals/Deck/Decals/"

## Default stickers: [file, center px (deck image space), scale, rotation].
@export var decorate := true
var default_decals := [
	["paperclip_note", Vector2(1010, 60), 0.36, 4.0],
	["dont_drift", Vector2(220, 58), 0.45, -3.0],
	["smiley_drip", Vector2(250, 398), 0.3, 12.0],
	["ghostwired", Vector2(1434, 290), 0.42, -4.0],
]

var heat := 0.0
var ram_total := 8
var ram_used := 0

var _lamps := {}           # key -> {"glow": ColorRect, "label": Label, "state": Lamp}
var _gauges: Control
var _header_label: Label
var _status_label: Label
var _cartridges: Array[Control] = []
var _time := 0.0
var _heat_light: PointLight2D
var _heat_focus: Control
var _program_carts := {}      # program_id -> cart Control
var _program_order: Array = []
var _ram_light: PointLight2D


func _ready() -> void:
	device_id = "deck_main"
	raise_on_pick = false
	super()
	_build_lamps()
	_build_text_strips()
	_gauges = Control.new()
	_gauges.name = "Gauges"
	_gauges.size = size
	_gauges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauges.draw.connect(_draw_gauges)
	add_child(_gauges)
	_build_lights()
	if has_rect("heat"):
		_heat_focus = Control.new()
		_heat_focus.name = "HeatFocus"
		_heat_focus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hr := get_rect_px("heat").grow(4)
		_heat_focus.position = hr.position
		_heat_focus.size = hr.size
		add_child(_heat_focus)
	if decorate:
		for d in default_decals:
			var path: String = DECAL_DIR + d[0] + ".png"
			if ResourceLoader.exists(path):
				add_decal(load(path), d[1], d[2], d[3])


func _process(delta: float) -> void:
	super(delta)
	_time += delta
	for key in _lamps:
		var l: Dictionary = _lamps[key]
		if l.state == Lamp.ALERT:
			var pulse := 0.55 + 0.45 * sin(_time * 9.0)
			l.glow.modulate.a = pulse
			l.label.modulate.a = 0.7 + 0.3 * pulse
			if l.light:
				l.light.energy = LAMP_LIGHT_ENERGY[Lamp.ALERT] * pulse
	if heat > 0.85:
		_gauges.queue_redraw()


# --- lamps --------------------------------------------------------------------------

func _build_lamps() -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for key in LAMP_KEYS:
		if not has_rect(key):
			continue
		var r := get_rect_px(key)
		var glow := ColorRect.new()
		glow.position = r.position + Vector2(3, 3)
		glow.size = r.size - Vector2(6, 6)
		glow.material = additive
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(glow)

		var lbl := Label.new()
		lbl.position = r.position
		lbl.size = r.size
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_override("font", FONT)
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.text = LAMP_DEFAULT_TEXT.get(key, "")
		add_child(lbl)

		var light := add_glow_light(r.get_center(), r.size * 0.5 + Vector2(46, 30), Color.WHITE, 0.0, 14.0)
		var hit := Control.new()
		hit.position = r.position
		hit.size = r.size
		hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hit.gui_input.connect(_on_lamp_input.bind(key))
		add_child(hit)
		_lamps[key] = {"glow": glow, "label": lbl, "state": Lamp.IDLE, "light": light, "hit": hit,
			"progress": -1.0, "sig": ""}
		set_lamp(key, Lamp.IDLE)


## key: "lamp_scan" / "lamp_lock" / "lamp_ic" / "lamp_aux" (or just "scan", "lock"...)
func set_lamp(key: String, state: Lamp, text: String = "") -> void:
	if not key.begins_with("lamp_"):
		key = "lamp_" + key
	if not _lamps.has(key):
		return
	var l: Dictionary = _lamps[key]
	l.state = state
	var c: Color = LAMP_COLORS[state]
	l.glow.color = c
	l.glow.modulate.a = 1.0
	var text_col := Color(c.r, c.g, c.b, 1.0).lerp(PHOSPHOR, 0.25)
	if state == Lamp.OFF:
		text_col = Color(0.2, 0.3, 0.22)
	elif state == Lamp.IDLE:
		text_col = Color(0.35, 0.6, 0.42)
	l.label.add_theme_color_override("font_color", text_col)
	l.label.modulate.a = 1.0
	if l.light:
		l.light.color = Color(c.r, c.g, c.b)
		l.light.energy = LAMP_LIGHT_ENERGY[state]
	if text != "":
		l.label.text = text


## Drive a lamp straight from game state colours (e.g. the terminal's scan/lock/IC colours).
## Desaturated colours read as "idle". progress: 0..1 shows a fill bar along the lens, <0 hides it.
func set_lamp_color(key: String, color: Color, text: String, progress := -1.0) -> void:
	if not key.begins_with("lamp_"):
		key = "lamp_" + key
	if not _lamps.has(key):
		return
	var l: Dictionary = _lamps[key]
	var sig := "%s|%s|%.3f" % [color.to_html(), text, progress]
	if l.sig == sig:
		return
	l.sig = sig
	l.state = Lamp.ACTIVE
	var idle := color.s < 0.15
	l.glow.color = Color(color.r, color.g, color.b, 0.03 if idle else 0.10)
	l.glow.modulate.a = 1.0
	if l.light:
		l.light.color = Color(color.r, color.g, color.b)
		l.light.energy = 0.25 if idle else 1.8
	var text_col := Color(0.35, 0.6, 0.42) if idle else Color(color.r, color.g, color.b, 1.0).lerp(PHOSPHOR, 0.2)
	l.label.add_theme_color_override("font_color", text_col)
	l.label.text = text.to_upper()
	_fit_label(l.label)
	l.progress = progress
	_gauges.queue_redraw()


func set_lamp_clickable(key: String, clickable: bool) -> void:
	if not key.begins_with("lamp_"):
		key = "lamp_" + key
	if not _lamps.has(key):
		return
	var hit: Control = _lamps[key].hit
	hit.mouse_filter = Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_IGNORE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW


func get_lamp_global_rect(key: String) -> Rect2:
	if not key.begins_with("lamp_"):
		key = "lamp_" + key
	if not _lamps.has(key):
		return Rect2()
	return (_lamps[key].hit as Control).get_global_rect()


## Transparent control over the heat gauge, for tutorial focus highlights.
func get_heat_focus_control() -> Control:
	return _heat_focus


func _on_lamp_input(event: InputEvent, key: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		lamp_pressed.emit(key)
		accept_event()


func _fit_label(lbl: Label, max_size := 22, min_size := 13, pad := 14.0) -> void:
	var font := lbl.get_theme_font("font")
	var avail := lbl.size.x - pad
	var fs := max_size
	while fs > min_size and font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail:
		fs -= 1
	lbl.add_theme_font_size_override("font_size", fs)


## Move an existing Control onto one of the deck's rects (e.g. the objective tracker onto screen2).
func host_panel(ctrl: Control, rect_key := "screen2", inset := Vector2(8, 6)) -> void:
	if ctrl == null or not has_rect(rect_key):
		return
	var r := get_rect_px(rect_key)
	if ctrl.get_parent() != null:
		ctrl.get_parent().remove_child(ctrl)
	add_child(ctrl)
	ctrl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ctrl.custom_minimum_size = Vector2.ZERO
	ctrl.position = r.position + inset
	ctrl.size = r.size - inset * 2.0
	if ctrl is PanelContainer:
		ctrl.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


# --- header / status strips ------------------------------------------------------------

func _build_text_strips() -> void:
	if has_rect("header"):
		_header_label = _make_strip_label(get_rect_px("header"), 16)
		_header_label.text = "DC_OS  |  [/cAl4x/pRk09s]"
	if has_rect("status"):
		_status_label = _make_strip_label(get_rect_px("status"), 18)
		_status_label.text = "UPTIME 00:00  |  LINK OK"


func _make_strip_label(r: Rect2, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.position = r.position + Vector2(10, 0)
	lbl.size = r.size - Vector2(20, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.clip_text = true
	lbl.add_theme_font_override("font", FONT)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.35))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	return lbl


func set_header(text: String) -> void:
	if _header_label:
		_header_label.text = text


func set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


# --- heat + RAM -------------------------------------------------------------------------

func set_heat(value: float) -> void:
	heat = clampf(value, 0.0, 1.0)
	_gauges.queue_redraw()
	_update_heat_light()


func set_ram(used: int, total: int = 8) -> void:
	ram_used = used
	ram_total = total
	_gauges.queue_redraw()
	if _ram_light:
		_ram_light.energy = 0.25 * ram_used


# --- lights -------------------------------------------------------------------------------

func _build_lights() -> void:
	if has_rect("header"):
		var h := get_rect_px("header")
		add_glow_light(h.get_center(), h.size * 0.5 + Vector2(40, 22), AMBER, 0.9, 10.0)
	if has_rect("status"):
		var st := get_rect_px("status")
		add_glow_light(st.get_center(), st.size * 0.5 + Vector2(36, 26), AMBER, 0.9, 10.0)
	if meta.get("points", {}).has("ram_0"):
		var p0 := get_point_px("ram_0")
		var p7 := get_point_px("ram_7")
		var half := (p7 - p0).abs() * 0.5 + Vector2(30, 26)
		_ram_light = add_glow_light((p0 + p7) * 0.5, half, Color(1.0, 0.55, 0.15), 0.0, 10.0)
	if has_rect("heat"):
		_heat_light = add_glow_light(get_rect_px("heat").get_center(), Vector2(60, 30), Color.WHITE, 0.0, 12.0)
	_update_heat_light()


func _heat_color(t: float) -> Color:
	var col := Color(0.25, 1.0, 0.45).lerp(Color(1.0, 0.75, 0.1), smoothstep(0.35, 0.65, t))
	return col.lerp(Color(1.0, 0.15, 0.1), smoothstep(0.7, 0.9, t))


func _update_heat_light() -> void:
	if _heat_light == null or not has_rect("heat"):
		return
	var r := get_rect_px("heat")
	var lit_w := r.size.x * heat
	_heat_light.position = Vector2(r.position.x + lit_w * 0.5, r.get_center().y)
	_heat_light.scale = Vector2(maxf(0.2, (lit_w * 0.5 + 50.0) / 60.0), 1.0)
	_heat_light.color = _heat_color(heat)
	_heat_light.energy = 0.0 if heat <= 0.0 else 1.6


func _draw_gauges() -> void:
	if has_rect("heat"):
		var r := get_rect_px("heat").grow(-3)
		var seg_w := 10.0
		var gap := 3.0
		var n := int(floor((r.size.x + gap) / (seg_w + gap)))
		var lit := int(round(heat * n))
		var flicker := 1.0
		if heat > 0.85:
			flicker = 0.75 + 0.25 * sin(_time * 14.0)
		for i in n:
			var t := float(i) / float(maxi(n - 1, 1))
			var col := Color(0.25, 1.0, 0.45).lerp(Color(1.0, 0.75, 0.1), smoothstep(0.35, 0.65, t))
			col = col.lerp(Color(1.0, 0.15, 0.1), smoothstep(0.7, 0.9, t))
			var x := r.position.x + i * (seg_w + gap)
			var seg := Rect2(x, r.position.y, seg_w, r.size.y)
			if i < lit:
				_gauges.draw_rect(seg.grow(2), Color(col.r, col.g, col.b, 0.18 * flicker))
				_gauges.draw_rect(seg, Color(col.r, col.g, col.b, 0.95 * flicker))
			else:
				_gauges.draw_rect(seg, Color(col.r, col.g, col.b, 0.07))

	for i in 8:
		var key := "ram_%d" % i
		if not meta.get("points", {}).has(key):
			continue
		var p := get_point_px(key)
		if i >= ram_total:
			continue
		if i < ram_used:
			_gauges.draw_circle(p, 11.0, Color(1.0, 0.55, 0.1, 0.18))
			_gauges.draw_circle(p, 5.0, Color(1.0, 0.65, 0.2, 0.95))
		else:
			_gauges.draw_circle(p, 4.0, Color(0.3, 0.6, 0.35, 0.35))

	for key in _lamps:
		var lp: Dictionary = _lamps[key]
		if lp.progress > 0.001 and lp.progress < 0.999:
			var lr := get_rect_px(key)
			var bar := Rect2(lr.position.x + 8, lr.end.y - 8, (lr.size.x - 16) * lp.progress, 3)
			var lc: Color = lp.light.color if lp.light else PHOSPHOR
			_gauges.draw_rect(Rect2(lr.position.x + 8, lr.end.y - 8, lr.size.x - 16, 3), Color(lc.r, lc.g, lc.b, 0.15))
			_gauges.draw_rect(bar, Color(lc.r, lc.g, lc.b, 0.95))

	if not _has_art and meta.get("points", {}).has("led_power"):
		_gauges.draw_circle(get_point_px("led_power"), 5.0, Color(0.3, 1.0, 0.5))


# --- program cartridges ---------------------------------------------------------------

## names / colors: one entry per filled slot (max 4). Empty string = empty slot.
func set_cartridges(names: Array, colors: Array = []) -> void:
	for c in _cartridges:
		c.queue_free()
	_cartridges.clear()
	var tex_path := art_dir + "cartridge.png"
	var tex: Texture2D = load(tex_path) if ResourceLoader.exists(tex_path) else null
	for i in names.size():
		var slot_key := "cart_slot_%d" % i
		if not has_rect(slot_key) or str(names[i]) == "":
			continue
		var slot := get_rect_px(slot_key)
		var cart := _make_cartridge(str(names[i]), colors[i] if i < colors.size() else Color(0.8, 0.8, 0.75), tex)
		cart.position = slot.position - Vector2(6, 6)   # cartridge render has a 6 px margin
		cart.set_meta("rest_y", cart.position.y)
		cart.gui_input.connect(_on_cartridge_input.bind(i, cart))
		add_child(cart)
		_cartridges.append(cart)


func _make_cartridge(label_text: String, tint: Color, tex: Texture2D) -> Control:
	var root := Control.new()
	root.size = Vector2(86, 118)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.size = root.size
		tr.modulate = tint
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr)
	else:
		var body := ColorRect.new()
		body.position = Vector2(6, 6)
		body.size = Vector2(74, 106)
		body.color = tint.darkened(0.55)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(body)
	var lbl := Label.new()
	lbl.position = Vector2(15, 43)
	lbl.size = Vector2(56, 56)
	lbl.text = label_text.to_upper()
	lbl.clip_text = true
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", FONT)
	_fit_label(lbl, 13, 8, 4.0)
	lbl.add_theme_color_override("font_color", Color(0.12, 0.11, 0.09))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lbl)
	return root


func _on_cartridge_input(event: InputEvent, index: int, cart: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var rest: float = cart.get_meta("rest_y")
		var t := create_tween()
		t.tween_property(cart, "position:y", rest + 7.0, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(cart, "modulate", Color(0.7, 0.7, 0.7), 0.06)
		t.tween_property(cart, "position:y", rest, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(cart, "modulate", Color.WHITE, 0.18)
		cartridge_pressed.emit(index)
		cart.accept_event()


# --- program cartridges (driven by ProgramManager via DeskLayer) ------------------------------

## programs: Array of Dictionaries {id, name, description, icon, state (ProgState), progress (0..1)}.
## Call every frame; cartridges are rebuilt only when the installed set changes.
func sync_programs(programs: Array, pulse_time: float) -> void:
	var ids: Array = []
	for p in programs:
		ids.append(p.id)
	if ids != _program_order:
		_rebuild_program_carts(programs)
	for p in programs:
		if _program_carts.has(p.id):
			_update_program_cart(_program_carts[p.id], p, pulse_time)


func _rebuild_program_carts(programs: Array) -> void:
	for c in _program_carts.values():
		if is_instance_valid(c):
			c.queue_free()
	_program_carts.clear()
	_program_order.clear()
	for c in _cartridges:
		c.queue_free()
	_cartridges.clear()
	var tex_path := art_dir + "cartridge.png"
	var tex: Texture2D = load(tex_path) if ResourceLoader.exists(tex_path) else null
	for i in programs.size():
		var p: Dictionary = programs[i]
		_program_order.append(p.id)
		var slot_key := "cart_slot_%d" % i
		if not has_rect(slot_key):
			push_warning("MainDeck: no cartridge slot for program %s" % p.id)
			continue
		var tint: Color = CART_TINTS[abs(hash(str(p.id))) % CART_TINTS.size()]
		var cart := _make_cartridge(str(p.get("name", p.id)), tint, tex)
		cart.position = get_rect_px(slot_key).position - Vector2(6, 6)
		cart.set_meta("rest_y", cart.position.y)
		cart.tooltip_text = "%s\n%s\n\nLeft click: load / use    Right click: eject" % [p.get("name", ""), p.get("description", "")]
		var icon_tex = p.get("icon")
		if icon_tex is Texture2D:
			var ic := TextureRect.new()
			ic.texture = icon_tex
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.position = Vector2(31, 46)
			ic.size = Vector2(24, 24)
			ic.modulate = Color(0.12, 0.11, 0.09)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cart.add_child(ic)
			var name_lbl: Label = cart.get_child(cart.get_child_count() - 2) as Label
			if name_lbl:
				name_lbl.position.y = 72
				name_lbl.size.y = 24
		var strip := ColorRect.new()
		strip.name = "Strip"
		strip.position = Vector2(15, 101)
		strip.size = Vector2(0, 4)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cart.add_child(strip)
		cart.gui_input.connect(_on_program_cart_input.bind(p.id, cart))
		add_child(cart)
		_program_carts[p.id] = cart


func _update_program_cart(cart: Control, p: Dictionary, pulse_time: float) -> void:
	var state: int = p.get("state", ProgState.DOCKED)
	var rest: float = cart.get_meta("rest_y")
	var seated := state != ProgState.DOCKED
	var target_y := rest + (10.0 if seated else 0.0)
	cart.position.y = lerpf(cart.position.y, target_y, 0.35)
	var strip := cart.get_node("Strip") as ColorRect
	if not seated:
		cart.modulate = Color.WHITE
		strip.size.x = 0.0
		return
	cart.modulate = Color(0.82, 0.82, 0.82)
	var col: Color = PROG_COLORS.get(state, Color.WHITE)
	if state == ProgState.RUNNING:
		col = col * (0.8 + 0.2 * sin(pulse_time * 4.0))
		col.a = 1.0
	strip.color = col
	strip.size.x = 56.0 * clampf(float(p.get("progress", 1.0)), 0.0, 1.0)


func _on_program_cart_input(event: InputEvent, program_id: StringName, cart: Control) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
		program_cartridge_pressed.emit(program_id, event.button_index)
		cart.accept_event()
