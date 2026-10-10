# device_shell.gd
# A physical piece of hardware on the desk: rendered chassis art, a screen slot that hosts
# ordinary Control UI, and pick-up / drag / snap behaviour.
#
# Art + layout come from Tools/Blender/build_deck.py:
#   res://Visuals/Deck/<device_id>.png   (beauty render)
#   res://Visuals/Deck/<device_id>.json  (screen / lamp / port rects in image pixels)
# If the renders are missing, the shell draws a flat placeholder from FALLBACK_META so the
# layout can be tested before Blender has run.

class_name DeviceShell
extends Control

signal picked_up(shell: DeviceShell)
signal dropped(shell: DeviceShell)

const SHADOW_SHADER := preload("res://Shaders/deck_soft_shadow.gdshader")
const GLASS_SHADER := preload("res://Shaders/deck_screen_glass.gdshader")

@export var device_id: String = "deck_main"
@export var art_dir: String = "res://Visuals/Deck/"
@export var draggable := true
@export var raise_on_pick := true
@export var lift_scale := 1.025
@export var shadow_offset := Vector2(6, 10)
@export var lifted_shadow_offset := Vector2(20, 32)
@export var snap_radius := 160.0
@export var keep_visible_px := 90.0
@export_group("Lighting")
## Use <id>_normal.png so 2D lights (screen spill, lamps) shade the bevels.
@export var use_normal_lighting := true
@export var screen_glow_color := Color(0.45, 1.0, 0.6)
@export var screen_glow_energy := 2.2
@export var screen_glow_spill := Vector2(90, 70)

## Only the chassis art is on this light layer, so lights never tint the screen UI.
const LIGHT_LAYER := 2

var meta: Dictionary = {}
var art: TextureRect
var shadow: TextureRect
var screen_slot: Control
var glass: ColorRect
var screen_flash: ColorRect
var screen_light: PointLight2D
var home_position := Vector2.ZERO
var snap_points: Array[Vector2] = []   # in parent coordinates (top-left of the shell)

var _has_art := false
var _dragging := false
var _drag_offset := Vector2.ZERO
var _last_mouse := Vector2.ZERO
var _velocity := Vector2.ZERO
var _tween: Tween
var _content: Control
static var _light_tex_cache := {}

# Mirrors build_deck.py so the placeholder lines up with the eventual renders.
const FALLBACK_META := {
	"deck_main": {
		"image_size": [1916, 496], "chassis_rect": [28, 28, 1860, 440],
		"rects": {
			"header": [346, 46, 1124, 24], "screen": [342, 90, 1132, 314],
			"lamp_scan": [66, 86, 232, 50], "lamp_lock": [66, 154, 232, 50],
			"lamp_ic": [66, 222, 232, 50], "lamp_aux": [66, 290, 232, 50],
			"status": [1522, 50, 326, 40], "screen2": [1524, 110, 322, 158],
			"cart_slot_0": [1520, 300, 74, 106], "cart_slot_1": [1604, 300, 74, 106],
			"cart_slot_2": [1688, 300, 74, 106], "cart_slot_3": [1772, 300, 74, 106],
			"heat": [54, 433, 1808, 18],
		},
		"points": {
			"exp_port_a": [1336, 25], "led_power": [174, 58],
			"ram_0": [112, 364], "ram_1": [138, 364], "ram_2": [164, 364], "ram_3": [190, 364],
			"ram_4": [216, 364], "ram_5": [242, 364], "ram_6": [268, 364], "ram_7": [294, 364],
		},
	},
	"aux_decrypt": {
		"image_size": [560, 510], "chassis_rect": [40, 40, 480, 430],
		"rects": {
			"screen": [68, 98, 424, 298], "handle": [186, 2, 188, 18],
			"key_0": [71, 419, 40, 32], "key_1": [125, 419, 40, 32],
			"key_2": [179, 419, 40, 32], "key_3": [233, 419, 40, 32],
		},
		"points": {"cable_port": [30, 131], "knob": [460, 435], "led_0": [302, 435], "led_1": [324, 435], "led_2": [346, 435]},
	},
	"cartridge": {
		"image_size": [86, 118], "chassis_rect": [6, 6, 74, 106],
		"rects": {"label": [15, 43, 56, 56]}, "points": {},
	},
}


func _ready() -> void:
	_load_meta()
	var img_size := _v2(meta.get("image_size", [400, 300]))
	size = img_size
	custom_minimum_size = img_size
	pivot_offset = img_size * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP

	var tex: Texture2D = null
	var tex_path := art_dir + device_id + ".png"
	if ResourceLoader.exists(tex_path):
		tex = load(tex_path)
	_has_art = tex != null

	shadow = TextureRect.new()
	shadow.name = "Shadow"
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.size = img_size
	shadow.position = shadow_offset
	shadow.show_behind_parent = true
	var sm := ShaderMaterial.new()
	sm.shader = SHADOW_SHADER
	shadow.material = sm
	add_child(shadow)

	art = TextureRect.new()
	art.name = "Art"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size = img_size
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture = tex
	art.light_mask = LIGHT_LAYER
	var nrm_path := art_dir + device_id + "_normal.png"
	if tex != null and use_normal_lighting and ResourceLoader.exists(nrm_path):
		var ct := CanvasTexture.new()
		ct.diffuse_texture = tex
		ct.normal_texture = load(nrm_path)
		art.texture = ct
	add_child(art)
	if _has_art:
		shadow.texture = tex
	else:
		shadow.texture = _placeholder_shadow_texture(img_size)

	if has_rect("screen"):
		var r := get_rect_px("screen")
		screen_slot = Control.new()
		screen_slot.name = "ScreenSlot"
		screen_slot.position = r.position
		screen_slot.size = r.size
		screen_slot.clip_contents = true
		screen_slot.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(screen_slot)

		glass = ColorRect.new()
		glass.name = "Glass"
		glass.position = r.position
		glass.size = r.size
		glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gm := ShaderMaterial.new()
		gm.shader = GLASS_SHADER
		glass.material = gm
		add_child(glass)

		screen_flash = ColorRect.new()
		screen_flash.name = "PowerFlash"
		screen_flash.position = r.position
		screen_flash.size = r.size
		screen_flash.pivot_offset = r.size * 0.5
		screen_flash.color = Color(0.75, 1.0, 0.85, 0.0)
		screen_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(screen_flash)

		screen_light = add_glow_light(r.get_center(), r.size * 0.5 + screen_glow_spill,
			screen_glow_color, screen_glow_energy, 18.0)

	home_position = position
	queue_redraw()


# --- metadata ----------------------------------------------------------------

func _load_meta() -> void:
	var json_path := art_dir + device_id + ".json"
	if FileAccess.file_exists(json_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if parsed is Dictionary:
			meta = parsed
			return
	meta = FALLBACK_META.get(device_id, {"image_size": [400, 300], "chassis_rect": [0, 0, 400, 300], "rects": {}, "points": {}})


func has_rect(key: String) -> bool:
	return meta.get("rects", {}).has(key)


func get_rect_px(key: String) -> Rect2:
	var r: Array = meta.get("rects", {}).get(key, [0, 0, 0, 0])
	return Rect2(r[0], r[1], r[2], r[3])


func get_point_px(key: String) -> Vector2:
	return _v2(meta.get("points", {}).get(key, [0, 0]))


func get_chassis_rect() -> Rect2:
	var r: Array = meta.get("chassis_rect", [0, 0, size.x, size.y])
	return Rect2(r[0], r[1], r[2], r[3])


## Global position of a metadata point, following the shell's scale / rotation.
func get_point_global(key: String) -> Vector2:
	return get_global_transform() * get_point_px(key)


func _v2(a) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(a[0], a[1])
	return Vector2.ZERO


# --- content -------------------------------------------------------------------

## Put a Control on this device's screen. Panel backgrounds are stripped so the glass shows,
## and content larger than the screen is scaled down to fit.
func set_content(content: Control, strip_panel_style := true) -> void:
	if screen_slot == null:
		push_warning("DeviceShell %s has no screen rect" % device_id)
		return
	_content = content
	if content.get_parent() != null:
		content.get_parent().remove_child(content)
	screen_slot.add_child(content)
	if strip_panel_style and content is PanelContainer:
		content.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	content.position = Vector2.ZERO
	await get_tree().process_frame
	if not is_instance_valid(content):
		return
	fit_content()


func fit_content() -> void:
	if _content == null or not is_instance_valid(_content):
		return
	var avail := screen_slot.size - Vector2(16, 16)
	var want := _content.get_combined_minimum_size()
	want.x = maxf(want.x, 1.0)
	want.y = maxf(want.y, 1.0)
	var s := minf(1.0, minf(avail.x / want.x, avail.y / want.y))
	_content.scale = Vector2(s, s)
	_content.size = want
	_content.position = (screen_slot.size - want * s) * 0.5


## Make content fill the screen exactly (for the terminal, which is a flexible layout).
func fill_content(content: Control, margin := Vector2(10, 6)) -> void:
	if screen_slot == null:
		return
	_content = content
	if content.get_parent() != null:
		content.get_parent().remove_child(content)
	screen_slot.add_child(content)
	content.set_anchors_preset(Control.PRESET_TOP_LEFT)
	content.scale = Vector2.ONE
	content.position = margin
	content.custom_minimum_size = Vector2.ZERO
	content.size = screen_slot.size - margin * 2.0


func get_content() -> Control:
	return _content


# --- screen power effects -------------------------------------------------------

func power_on(duration := 0.35) -> void:
	if screen_flash == null:
		return
	screen_flash.scale = Vector2(1.0, 0.01)
	screen_flash.color.a = 0.9
	if screen_slot:
		screen_slot.modulate.a = 0.0
	var t := create_tween()
	if screen_light:
		screen_light.energy = 0.0
		t.parallel().tween_property(screen_light, "energy", screen_glow_energy, duration).set_delay(duration * 0.2)
	t.tween_property(screen_flash, "scale:y", 1.0, duration * 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(screen_slot, "modulate:a", 1.0, duration * 0.5).set_delay(duration * 0.2)
	t.tween_property(screen_flash, "color:a", 0.0, duration * 0.5)


func power_off(duration := 0.25) -> Tween:
	var t := create_tween()
	if screen_flash == null:
		return t
	screen_flash.scale = Vector2.ONE
	t.tween_property(screen_flash, "color:a", 0.85, duration * 0.3)
	if screen_light:
		t.parallel().tween_property(screen_light, "energy", 0.0, duration * 0.6)
	t.parallel().tween_property(screen_slot, "modulate:a", 0.0, duration * 0.3)
	t.tween_property(screen_flash, "scale:y", 0.01, duration * 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	t.tween_property(screen_flash, "color:a", 0.0, duration * 0.3)
	return t


# --- dragging ---------------------------------------------------------------------

func _has_point(point: Vector2) -> bool:
	if get_chassis_rect().grow(4).has_point(point):
		return true
	for key in meta.get("rects", {}):
		if str(key).begins_with("handle") and get_rect_px(key).grow(6).has_point(point):
			return true
	return false


func _gui_input(event: InputEvent) -> void:
	if not draggable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.double_click:
			_dragging = false
			return_home()
			accept_event()
		elif event.pressed:
			_begin_drag(_event_canvas_pos(event))
			accept_event()
		elif _dragging:
			_end_drag()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mouse := _event_canvas_pos(event)
		_velocity = _velocity.lerp((mouse - _last_mouse) / maxf(get_process_delta_time(), 0.001), 0.3)
		_last_mouse = mouse
		global_position = _clamp_to_viewport(mouse - _drag_offset)
		accept_event()


func _process(delta: float) -> void:
	if _dragging:
		# a little swing in the direction of travel sells the weight
		var target_rot := clampf(_velocity.x * 0.00003, -0.035, 0.035)
		rotation = lerpf(rotation, target_rot, minf(1.0, delta * 10.0))
		_velocity = _velocity.lerp(Vector2.ZERO, minf(1.0, delta * 6.0))


## Pointer position in this control's canvas space (robust to viewport stretch).
func _event_canvas_pos(event: InputEventMouse) -> Vector2:
	return get_canvas_transform().affine_inverse() * event.global_position


func _begin_drag(mouse: Vector2) -> void:
	_dragging = true
	_last_mouse = mouse
	_velocity = Vector2.ZERO
	_drag_offset = _last_mouse - global_position
	if raise_on_pick and get_parent() != null:
		get_parent().move_child(self, -1)
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "scale", Vector2(lift_scale, lift_scale), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(shadow, "position", lifted_shadow_offset, 0.12)
	_tween.tween_property(shadow, "modulate:a", 0.75, 0.12)
	picked_up.emit(self)


func _end_drag() -> void:
	_dragging = false
	var target := position
	var best := snap_radius
	for p in snap_points:
		var d := p.distance_to(position)
		if d < best:
			best = d
			target = p
	_settle_at(target)
	dropped.emit(self)


func return_home() -> void:
	_settle_at(home_position)


func _settle_at(target: Vector2) -> void:
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position", target, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_tween.tween_property(shadow, "position", shadow_offset, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(shadow, "modulate:a", 1.0, 0.18)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _clamp_to_viewport(pos: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	var c := get_chassis_rect()
	var min_x := keep_visible_px - (c.position.x + c.size.x)
	var max_x := vp.x - keep_visible_px - c.position.x
	var min_y := keep_visible_px - (c.position.y + c.size.y)
	var max_y := vp.y - keep_visible_px - c.position.y
	return Vector2(clampf(pos.x, min_x, max_x), clampf(pos.y, min_y, max_y))


# --- lights + decals ------------------------------------------------------------------------

## Soft elliptical light that only touches this device's chassis art (shaded by its normal map).
## center: device px. extent: half-size of the ellipse in px.
func add_glow_light(center: Vector2, extent: Vector2, color: Color, energy: float, height := 20.0) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = _ellipse_texture(extent)
	l.position = center
	l.color = color
	l.energy = energy
	l.height = height
	l.range_item_cull_mask = LIGHT_LAYER
	l.blend_mode = Light2D.BLEND_MODE_ADD
	add_child(l)
	return l


func _ellipse_texture(extent: Vector2) -> Texture2D:
	var key := Vector2i(extent.round())
	if _light_tex_cache.has(key):
		return _light_tex_cache[key]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1))
	g.set_color(1, Color(0, 0, 0))
	g.add_point(0.45, Color(0.55, 0.55, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = maxi(8, key.x * 2)
	t.height = maxi(8, key.y * 2)
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_light_tex_cache[key] = t
	return t


## Slap a sticker on the hardware. center: device px. Drawn above screens and cartridges.
func add_decal(tex: Texture2D, center: Vector2, decal_scale := 0.5, rotation_deg := 0.0) -> TextureRect:
	if tex == null:
		return null
	var d := TextureRect.new()
	d.texture = tex
	d.size = tex.get_size()
	d.pivot_offset = d.size * 0.5
	d.position = center - d.size * 0.5
	d.scale = Vector2(decal_scale, decal_scale)
	d.rotation_degrees = rotation_deg
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.light_mask = LIGHT_LAYER
	add_child(d)
	return d


# --- placeholder (no renders yet) ------------------------------------------------------

func _draw() -> void:
	if _has_art:
		return
	var c := get_chassis_rect()
	draw_rect(c, Color(0.16, 0.17, 0.14))
	draw_rect(c, Color(0.32, 0.33, 0.28), false, 3.0)
	for key in meta.get("rects", {}):
		var r := get_rect_px(key)
		var col := Color(0.03, 0.05, 0.04)
		if key.begins_with("lamp"):
			col = Color(0.03, 0.09, 0.05)
		elif key.begins_with("key"):
			col = Color(0.07, 0.07, 0.07)
		elif key == "handle":
			col = Color(0.08, 0.08, 0.08)
		draw_rect(r, col)
		draw_rect(r, Color(0.0, 0.0, 0.0, 0.8), false, 2.0)
	for key in meta.get("points", {}):
		draw_circle(get_point_px(key), 5.0, Color(0.25, 0.12, 0.05))


func _placeholder_shadow_texture(img_size: Vector2) -> Texture2D:
	var img := Image.create(int(img_size.x), int(img_size.y), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := get_chassis_rect()
	img.fill_rect(Rect2i(c), Color(0, 0, 0, 1))
	return ImageTexture.create_from_image(img)
