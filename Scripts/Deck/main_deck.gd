# main_deck.gd
# The player's deck: wide terminal screen plus the physical indicators around it.
# All indicator positions come from the Blender metadata (deck_main.json), so the
# lamps / gauges always sit exactly on the rendered hardware.

class_name MainDeck
extends DeviceShell

signal cartridge_pressed(index: int)

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
	["paperclip_note", Vector2(1436, 98), 0.5, 5.0],
	["dont_drift", Vector2(212, 58), 0.52, -3.0],
	["smiley_drip", Vector2(290, 398), 0.3, 12.0],
	["ghostwired", Vector2(1772, 290), 0.42, -4.0],
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
		_lamps[key] = {"glow": glow, "label": lbl, "state": Lamp.IDLE, "light": light}
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
		_ram_light = add_glow_light((p0 + p7) * 0.5, Vector2((p7.x - p0.x) * 0.5 + 30, 26), Color(1.0, 0.55, 0.15), 0.0, 10.0)
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
	lbl.text = label_text
	lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", FONT)
	lbl.add_theme_font_size_override("font_size", 13)
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
