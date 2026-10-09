# WireframeModels.gd
# Small library of wireframe objects drawn on the facility map: vehicles,
# furniture, and the physical side of signals (valves, fabricators, panels).
#
# A model is a footprint plus a list of parts. Part x/y are normalized to the
# footprint (0..1, x right, y down); heights (z) are in pixels and drawn with an
# oblique projection so boxes read as 3D. `size` is the footprint in pixels
# used when the model sits under a signal; props scale it to their rect.

class_name WireframeModels extends RefCounted

# Screen offset per pixel of height (up and slightly left).
const HEIGHT_PROJECTION := Vector2(-0.32, -0.55)

# Signal id prefix -> model, used when a signal has no explicit map_model.
const SIGNAL_MODEL_BY_PREFIX := {
	"coolant_vent": &"coolant_valve",
	"nano_fabricator": &"nanofab",
	"breaker_panel": &"breaker_panel",
	"null_terminal": &"interface_rig",
	"override_terminal": &"console",
	"archive_terminal": &"console",
	"fabricator": &"nanofab",
}

static var _cache: Dictionary = {}

static func model_for_signal(data: SignalData) -> StringName:
	if data == null:
		return &""
	if data.map_model != &"":
		return data.map_model
	for prefix in SIGNAL_MODEL_BY_PREFIX:
		if data.system_id.begins_with(prefix):
			return SIGNAL_MODEL_BY_PREFIX[prefix]
	return &""

static func get_model(model_name: StringName) -> Dictionary:
	if model_name == &"":
		return {}
	if _cache.is_empty():
		_build()
	return _cache.get(model_name, {})

static func has_model(model_name: StringName) -> bool:
	return not get_model(model_name).is_empty()

# --- part constructors ---

static func _box(x: float, y: float, w: float, h: float, z0: float, z1: float) -> Dictionary:
	return {"t": "box", "r": Rect2(x, y, w, h), "z": Vector2(z0, z1)}

static func _cyl(cx: float, cy: float, radius: float, z0: float, z1: float) -> Dictionary:
	return {"t": "cyl", "c": Vector2(cx, cy), "rad": radius, "z": Vector2(z0, z1)}

static func _ring(cx: float, cy: float, radius: float, z: float) -> Dictionary:
	return {"t": "ring", "c": Vector2(cx, cy), "rad": radius, "z": z}

static func _seg(ax: float, ay: float, az: float, bx: float, by: float, bz: float) -> Dictionary:
	return {"t": "line", "a": Vector3(ax, ay, az), "b": Vector3(bx, by, bz)}

# --- library ---

static func _build() -> void:
	# Vehicles / exterior
	_cache[&"van"] = {"size": Vector2(300, 110), "parts": [
		_box(0.0, 0.08, 0.76, 0.84, 4, 40),          # cargo box
		_box(0.76, 0.12, 0.22, 0.76, 4, 28),         # cab
		_seg(0.80, 0.14, 28, 0.80, 0.86, 28),        # windshield edge
		_seg(0.0, 0.5, 4, 0.0, 0.5, 40),             # rear door split
		_seg(0.08, 0.08, 40, 0.68, 0.08, 40),
		_seg(0.08, 0.30, 40, 0.68, 0.30, 40),        # roof rails
		_seg(0.08, 0.70, 40, 0.68, 0.70, 40),
		_box(0.12, 0.0, 0.14, 0.08, 0, 10),          # wheels
		_box(0.12, 0.92, 0.14, 0.08, 0, 10),
		_box(0.74, 0.0, 0.14, 0.08, 0, 10),
		_box(0.74, 0.92, 0.14, 0.08, 0, 10),
	]}
	_cache[&"guard_booth"] = {"size": Vector2(200, 200), "parts": [
		_box(0.1, 0.1, 0.8, 0.8, 0, 58),
		_box(0.04, 0.04, 0.92, 0.92, 58, 64),        # roof overhang
		_seg(0.1, 0.5, 26, 0.1, 0.5, 48),
		_seg(0.1, 0.25, 48, 0.1, 0.75, 48),          # window
		_seg(0.1, 0.25, 26, 0.1, 0.75, 26),
	]}

	# Interior furniture
	_cache[&"reception"] = {"size": Vector2(420, 80), "parts": [
		_box(0.0, 0.35, 1.0, 0.65, 0, 26),           # counter
		_box(0.0, 0.0, 0.1, 0.35, 0, 26),            # return
		_box(0.3, 0.45, 0.12, 0.25, 26, 40),         # monitors
		_box(0.6, 0.45, 0.12, 0.25, 26, 40),
	]}
	_cache[&"lockers"] = {"size": Vector2(190, 80), "parts": [
		_box(0.0, 0.0, 1.0, 1.0, 0, 56),
		_seg(0.25, 0.0, 56, 0.25, 1.0, 56),          # locker divisions (top face)
		_seg(0.5, 0.0, 56, 0.5, 1.0, 56),
		_seg(0.75, 0.0, 56, 0.75, 1.0, 56),
	]}
	_cache[&"carts"] = {"size": Vector2(240, 80), "parts": [
		_box(0.05, 0.15, 0.38, 0.7, 4, 22),
		_seg(0.05, 0.15, 22, 0.0, 0.15, 34),
		_seg(0.05, 0.85, 22, 0.0, 0.85, 34),
		_seg(0.0, 0.15, 34, 0.0, 0.85, 34),
		_box(0.55, 0.15, 0.38, 0.7, 4, 22),
		_box(0.6, 0.25, 0.14, 0.25, 22, 34),         # crate on the cart
	]}
	_cache[&"decon_shower"] = {"size": Vector2(600, 50), "parts": [
		_box(0.0, 0.0, 0.03, 1.0, 0, 62),
		_box(0.33, 0.0, 0.03, 1.0, 0, 62),
		_box(0.66, 0.0, 0.03, 1.0, 0, 62),
		_box(0.97, 0.0, 0.03, 1.0, 0, 62),
		_seg(0.0, 0.5, 62, 1.0, 0.5, 62),            # spray bar
		_ring(0.17, 0.5, 0.25, 58),
		_ring(0.5, 0.5, 0.25, 58),
		_ring(0.83, 0.5, 0.25, 58),
	]}
	_cache[&"charging_rack"] = {"size": Vector2(720, 70), "parts": [
		_box(0.0, 0.0, 1.0, 1.0, 0, 8),
		_box(0.02, 0.1, 0.2, 0.8, 8, 20),
		_box(0.27, 0.1, 0.2, 0.8, 8, 20),
		_box(0.52, 0.1, 0.2, 0.8, 8, 20),
		_box(0.77, 0.1, 0.2, 0.8, 8, 20),
		_seg(0.0, 0.0, 8, 0.0, 0.0, 44),
		_seg(1.0, 0.0, 8, 1.0, 0.0, 44),
		_seg(0.0, 0.0, 44, 1.0, 0.0, 44),            # gantry
	]}
	_cache[&"plinth"] = {"size": Vector2(240, 100), "parts": [
		_box(0.0, 0.0, 1.0, 1.0, 0, 6),
		_box(0.1, 0.1, 0.8, 0.8, 6, 10),
	]}

	# Signal hardware
	_cache[&"coolant_valve"] = {"size": Vector2(130, 84), "parts": [
		_box(0.0, 0.38, 1.0, 0.24, 6, 18),           # pipe run
		_cyl(0.5, 0.5, 0.28, 0, 30),                 # valve body
		_seg(0.5, 0.5, 30, 0.5, 0.5, 44),            # stem
		_ring(0.5, 0.5, 0.42, 44),                   # handwheel
		_seg(0.29, 0.5, 44, 0.71, 0.5, 44),
		_seg(0.5, 0.29, 44, 0.5, 0.71, 44),
	]}
	_cache[&"nanofab"] = {"size": Vector2(144, 96), "parts": [
		_box(0.0, 0.1, 1.0, 0.8, 0, 36),             # cabinet
		_box(0.15, 0.25, 0.4, 0.5, 36, 50),          # hopper
		_cyl(0.78, 0.5, 0.12, 36, 46),               # extruder head
		_seg(0.0, 0.5, 8, 1.0, 0.5, 8),              # output tray lip
	]}
	_cache[&"breaker_panel"] = {"size": Vector2(124, 50), "parts": [
		_box(0.0, 0.0, 1.0, 1.0, 10, 64),
		_seg(0.5, 1.0, 10, 0.5, 1.0, 64),            # door split
		_seg(0.15, 1.0, 50, 0.85, 1.0, 50),
		_box(0.4, 0.0, 0.2, 0.3, 64, 74),            # conduit
	]}
	_cache[&"console"] = {"size": Vector2(130, 84), "parts": [
		_box(0.0, 0.3, 1.0, 0.7, 0, 24),             # desk
		_seg(0.1, 0.3, 24, 0.1, 0.1, 44),            # screen
		_seg(0.9, 0.3, 24, 0.9, 0.1, 44),
		_seg(0.1, 0.1, 44, 0.9, 0.1, 44),
		_seg(0.1, 0.3, 24, 0.9, 0.3, 24),
	]}
	_cache[&"interface_rig"] = {"size": Vector2(190, 120), "parts": [
		_box(0.0, 0.0, 1.0, 1.0, 0, 6),              # platform
		_cyl(0.5, 0.5, 0.22, 6, 40),                 # core
		_ring(0.5, 0.5, 0.42, 30),                   # halo
		_seg(0.08, 0.5, 6, 0.28, 0.5, 30),           # struts
		_seg(0.92, 0.5, 6, 0.72, 0.5, 30),
		_seg(0.5, 0.08, 6, 0.5, 0.28, 30),
	]}
