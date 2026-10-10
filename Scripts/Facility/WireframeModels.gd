# WireframeModels.gd
# Prop library: the wireframe objects drawn on the facility map. Covers both
# set dressing (cars, desks, racks...) and the physical side of signals
# (valves, printers, consoles...). Define a thing once here and reuse it
# everywhere: rooms place it with RoomBuilder.place()/row()/prop(), signals
# show it with spawn(...).model() or an id prefix (SIGNAL_MODEL_BY_PREFIX).
#
# A model is a footprint plus a list of parts. Part x/y are normalized to the
# footprint (0..1, x right, y down); heights (z) are in pixels and drawn with an
# oblique projection so boxes read as 3D.
#
# `size` is the model's default footprint in map pixels. It's used when the
# model sits under a signal, and by RoomBuilder.place()/row() to size props.
# Rough scale for new models: ~40 px per metre on the floor, heights stylised
# at ~20 px per metre. (A cell is 240 px wide, a lane 90 px tall.)
#
# Orientation: rot 0 is the model as authored; for vehicles and furniture the
# "front" faces +x (right). Rotations are quarter turns clockwise, so rot 1
# faces down, rot 2 faces left, rot 3 faces up.
#
# Catalogue (see _build for details):
#   Vehicles:    van, car, box_truck, forklift
#   Exterior:    guard_booth, ticket_booth, barrier_arm, bollard, ev_charger,
#                dumpster, planter, bench, hvac_unit, pillar
#   Logistics:   pallet, pallet_stack, crate, carts, dock_leveler, shelving_rack
#   Circulation: stairs, elevator_car
#   Office:      desk, desk_cluster, meeting_table, meeting_pod, sofa, plant,
#                reception, printer, coffee_bar, coffee_machine, water_cooler,
#                vending_machine, conference_display, kiosk, filing_cabinet
#   Records/IT:  filing_stacks, scanner_station, shredder, server_rack, cage,
#                vault_door
#   Facility:    lockers, decon_shower, charging_rack, plinth, cleaning_bot
#   Signal hw:   coolant_valve, nanofab, breaker_panel, console, interface_rig

class_name WireframeModels extends RefCounted

# Screen offset per pixel of height (up and slightly left).
const HEIGHT_PROJECTION := Vector2(-0.32, -0.55)

# Authoring scale, used to turn a model's pixel size into cells/lanes when
# placing props. Matches the 1920px viewport (8 cells) and 90px map lanes.
const PX_PER_CELL := 240.0
const PX_PER_LANE := 90.0

# Signal id prefix -> model, used when a signal has no explicit map_model.
const SIGNAL_MODEL_BY_PREFIX := {
	"coolant_vent": &"coolant_valve",
	"nano_fabricator": &"nanofab",
	"breaker_panel": &"breaker_panel",
	"null_terminal": &"interface_rig",
	"override_terminal": &"console",
	"archive_terminal": &"console",
	"fabricator": &"nanofab",
	"printer": &"printer",
	"coffee": &"coffee_machine",
	"vending": &"vending_machine",
	"kiosk": &"kiosk",
	"car_alarm": &"car",
	"ev_charger": &"ev_charger",
	"cleaning_bot": &"cleaning_bot",
	"server_rack": &"server_rack",
	"barrier": &"barrier_arm",
	"display": &"conference_display",
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

static func get_model_names() -> Array:
	if _cache.is_empty():
		_build()
	return _cache.keys()

# Default footprint in (cells, lanes) for a model at a given rotation.
static func get_footprint_cells(model_name: StringName, rot: int = 0) -> Vector2:
	var model := get_model(model_name)
	if model.is_empty():
		return Vector2(0.5, 0.5)
	var size: Vector2 = model["size"]
	if posmod(rot, 2) == 1:
		size = Vector2(size.y, size.x)
	return Vector2(size.x / PX_PER_CELL, size.y / PX_PER_LANE)

# Rotates a normalized footprint point by `rot` quarter turns clockwise.
static func rotate_point(p: Vector2, rot: int) -> Vector2:
	match posmod(rot, 4):
		1:
			return Vector2(1.0 - p.y, p.x)
		2:
			return Vector2(1.0 - p.x, 1.0 - p.y)
		3:
			return Vector2(p.y, 1.0 - p.x)
	return p

static func rotate_rect(r: Rect2, rot: int) -> Rect2:
	var a := rotate_point(r.position, rot)
	var b := rotate_point(r.end, rot)
	var top_left := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	return Rect2(top_left, (a - b).abs())

# --- part constructors ---

static func _box(x: float, y: float, w: float, h: float, z0: float, z1: float) -> Dictionary:
	return {"t": "box", "r": Rect2(x, y, w, h), "z": Vector2(z0, z1)}

static func _cyl(cx: float, cy: float, radius: float, z0: float, z1: float) -> Dictionary:
	return {"t": "cyl", "c": Vector2(cx, cy), "rad": radius, "z": Vector2(z0, z1)}

static func _ring(cx: float, cy: float, radius: float, z: float) -> Dictionary:
	return {"t": "ring", "c": Vector2(cx, cy), "rad": radius, "z": z}

static func _seg(ax: float, ay: float, az: float, bx: float, by: float, bz: float) -> Dictionary:
	return {"t": "line", "a": Vector3(ax, ay, az), "b": Vector3(bx, by, bz)}

# Four wheels as small blocks at the given x positions.
static func _wheels(x_front: float, x_rear: float, w: float = 0.12, depth: float = 0.08) -> Array:
	return [
		_box(x_rear, 0.0, w, depth, 0, 8),
		_box(x_rear, 1.0 - depth, w, depth, 0, 8),
		_box(x_front, 0.0, w, depth, 0, 8),
		_box(x_front, 1.0 - depth, w, depth, 0, 8),
	]

static func _add(model_name: StringName, size: Vector2, parts: Array) -> void:
	_cache[model_name] = {"size": size, "parts": parts}

# --- library ---

static func _build() -> void:
	_build_vehicles()
	_build_exterior()
	_build_logistics()
	_build_circulation()
	_build_office()
	_build_records()
	_build_facility()
	_build_signal_hardware()

static func _build_vehicles() -> void:
	_add(&"van", Vector2(300, 110), [
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
	])
	_add(&"car", Vector2(180, 76), [
		_box(0.02, 0.1, 0.96, 0.8, 4, 14),           # body
		_box(0.28, 0.16, 0.44, 0.68, 14, 26),        # cabin
		_seg(0.72, 0.16, 26, 0.84, 0.2, 14),         # windshield rake
		_seg(0.72, 0.84, 26, 0.84, 0.8, 14),
		_seg(0.28, 0.16, 26, 0.18, 0.2, 14),         # rear window rake
		_seg(0.28, 0.84, 26, 0.18, 0.8, 14),
	] + _wheels(0.72, 0.14, 0.14, 0.1))
	_add(&"box_truck", Vector2(340, 100), [
		_box(0.0, 0.04, 0.72, 0.92, 6, 54),          # cargo box
		_box(0.74, 0.1, 0.24, 0.8, 6, 34),           # cab
		_seg(0.80, 0.12, 34, 0.80, 0.88, 34),        # windshield edge
		_seg(0.0, 0.5, 6, 0.0, 0.5, 54),             # roll door split
		_seg(0.0, 0.04, 30, 0.0, 0.96, 30),
	] + _wheels(0.78, 0.1, 0.12, 0.06))
	_add(&"forklift", Vector2(110, 60), [
		_box(0.22, 0.12, 0.62, 0.76, 4, 18),         # body / counterweight
		_box(0.4, 0.2, 0.36, 0.6, 18, 20),           # seat deck
		_seg(0.42, 0.18, 18, 0.42, 0.18, 40),        # overhead guard posts
		_seg(0.42, 0.82, 18, 0.42, 0.82, 40),
		_seg(0.78, 0.18, 18, 0.78, 0.82, 40),
		_box(0.42, 0.18, 0.36, 0.64, 40, 41),        # guard roof
		_seg(0.18, 0.2, 0, 0.18, 0.2, 52),           # mast
		_seg(0.18, 0.8, 0, 0.18, 0.8, 52),
		_seg(0.18, 0.2, 52, 0.18, 0.8, 52),
		_seg(0.18, 0.3, 3, 0.0, 0.3, 3),             # forks
		_seg(0.18, 0.7, 3, 0.0, 0.7, 3),
	])

static func _build_exterior() -> void:
	_add(&"guard_booth", Vector2(200, 200), [
		_box(0.1, 0.1, 0.8, 0.8, 0, 58),
		_box(0.04, 0.04, 0.92, 0.92, 58, 64),        # roof overhang
		_seg(0.1, 0.5, 26, 0.1, 0.5, 48),
		_seg(0.1, 0.25, 48, 0.1, 0.75, 48),          # window
		_seg(0.1, 0.25, 26, 0.1, 0.75, 26),
	])
	_add(&"ticket_booth", Vector2(90, 80), [
		_box(0.1, 0.1, 0.8, 0.8, 0, 46),
		_box(0.04, 0.04, 0.92, 0.92, 46, 50),        # roof
		_seg(0.9, 0.2, 22, 0.9, 0.8, 22),            # service window
		_seg(0.9, 0.2, 38, 0.9, 0.8, 38),
	])
	_add(&"barrier_arm", Vector2(170, 24), [
		_box(0.0, 0.1, 0.12, 0.8, 0, 26),            # post / motor box
		_seg(0.06, 0.5, 24, 1.0, 0.5, 24),           # arm
		_seg(0.4, 0.5, 24, 0.4, 0.5, 20),            # stripe ticks
		_seg(0.7, 0.5, 24, 0.7, 0.5, 20),
	])
	_add(&"bollard", Vector2(16, 16), [
		_cyl(0.5, 0.5, 0.45, 0, 18),
	])
	_add(&"ev_charger", Vector2(30, 22), [
		_box(0.15, 0.2, 0.7, 0.6, 0, 40),
		_seg(0.15, 0.5, 30, -0.3, 0.9, 6),           # cable
	])
	_add(&"dumpster", Vector2(100, 60), [
		_box(0.0, 0.0, 1.0, 1.0, 2, 30),
		_seg(0.0, 0.0, 30, 0.0, 1.0, 34),            # sloped lid
		_seg(1.0, 0.0, 30, 1.0, 1.0, 34),
		_seg(0.0, 0.5, 34, 1.0, 0.5, 34),            # lid split
	])
	_add(&"planter", Vector2(120, 40), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 12),
		_ring(0.2, 0.5, 0.3, 18),
		_ring(0.5, 0.5, 0.36, 22),
		_ring(0.8, 0.5, 0.3, 18),
	])
	_add(&"bench", Vector2(100, 30), [
		_box(0.0, 0.2, 1.0, 0.6, 9, 11),             # seat
		_seg(0.1, 0.5, 0, 0.1, 0.5, 9),
		_seg(0.9, 0.5, 0, 0.9, 0.5, 9),
		_seg(0.0, 0.15, 20, 1.0, 0.15, 20),          # backrest
	])
	_add(&"hvac_unit", Vector2(120, 90), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 34),
		_ring(0.28, 0.5, 0.3, 34),                   # fans
		_ring(0.72, 0.5, 0.3, 34),
		_seg(0.28, 0.2, 34, 0.28, 0.8, 34),
		_seg(0.72, 0.2, 34, 0.72, 0.8, 34),
	])
	_add(&"pillar", Vector2(36, 36), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 70),
		_box(-0.1, -0.1, 1.2, 1.2, 0, 8),            # base plinth
	])

static func _build_logistics() -> void:
	_add(&"pallet", Vector2(50, 50), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 5),
		_seg(0.33, 0.0, 5, 0.33, 1.0, 5),
		_seg(0.66, 0.0, 5, 0.66, 1.0, 5),
	])
	_add(&"pallet_stack", Vector2(50, 50), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 5),              # pallet
		_box(0.06, 0.06, 0.88, 0.88, 5, 30),         # wrapped load
		_seg(0.5, 0.06, 30, 0.5, 0.94, 30),          # strap
	])
	_add(&"crate", Vector2(44, 44), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 26),
		_seg(0.0, 0.0, 26, 1.0, 1.0, 26),
		_seg(1.0, 0.0, 26, 0.0, 1.0, 26),
	])
	_add(&"carts", Vector2(240, 80), [
		_box(0.05, 0.15, 0.38, 0.7, 4, 22),
		_seg(0.05, 0.15, 22, 0.0, 0.15, 34),
		_seg(0.05, 0.85, 22, 0.0, 0.85, 34),
		_seg(0.0, 0.15, 34, 0.0, 0.85, 34),
		_box(0.55, 0.15, 0.38, 0.7, 4, 22),
		_box(0.6, 0.25, 0.14, 0.25, 22, 34),         # crate on the cart
	])
	_add(&"dock_leveler", Vector2(110, 90), [
		_box(0.0, 0.05, 1.0, 0.9, 0, 3),             # plate
		_seg(0.0, 0.05, 3, 1.0, 0.95, 3),
		_box(0.0, 0.0, 0.12, 0.08, 0, 14),           # bumpers
		_box(0.0, 0.92, 0.12, 0.08, 0, 14),
	])
	_add(&"shelving_rack", Vector2(240, 44), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 2),
		_box(0.0, 0.0, 1.0, 1.0, 22, 23),            # shelf levels
		_box(0.0, 0.0, 1.0, 1.0, 44, 45),
		_box(0.0, 0.0, 1.0, 1.0, 66, 67),
		_seg(0.0, 0.0, 0, 0.0, 0.0, 67),             # uprights
		_seg(0.5, 0.0, 0, 0.5, 0.0, 67),
		_seg(1.0, 0.0, 0, 1.0, 0.0, 67),
		_box(0.08, 0.1, 0.18, 0.8, 23, 38),          # stock
		_box(0.6, 0.1, 0.26, 0.8, 45, 58),
	])

static func _build_circulation() -> void:
	# Flight of stairs going "down" toward +x: treads step lower as x grows.
	_add(&"stairs", Vector2(150, 70), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 1),
		_seg(0.15, 0.0, 1, 0.15, 1.0, 1),
		_seg(0.3, 0.0, 1, 0.3, 1.0, 1),
		_seg(0.45, 0.0, 1, 0.45, 1.0, 1),
		_seg(0.6, 0.0, 1, 0.6, 1.0, 1),
		_seg(0.75, 0.0, 1, 0.75, 1.0, 1),
		_seg(0.9, 0.0, 1, 0.9, 1.0, 1),
		_seg(0.0, 0.0, 30, 1.0, 0.0, 30),            # handrails
		_seg(0.0, 1.0, 30, 1.0, 1.0, 30),
		_seg(0.15, 0.5, 1, 0.6, 0.5, 1),             # down arrow
		_seg(0.6, 0.5, 1, 0.5, 0.35, 1),
		_seg(0.6, 0.5, 1, 0.5, 0.65, 1),
	])
	# Freight elevator car with doors on the +x side.
	_add(&"elevator_car", Vector2(130, 120), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 2),              # floor
		_box(0.0, 0.0, 0.05, 1.0, 0, 64),            # back wall
		_box(0.0, 0.0, 1.0, 0.05, 0, 64),            # side walls
		_box(0.0, 0.95, 1.0, 0.05, 0, 64),
		_seg(1.0, 0.05, 0, 1.0, 0.05, 64),           # door frame
		_seg(1.0, 0.95, 0, 1.0, 0.95, 64),
		_seg(1.0, 0.05, 64, 1.0, 0.95, 64),
		_seg(1.0, 0.5, 0, 1.0, 0.5, 64),             # door split
		_box(0.86, 0.06, 0.08, 0.1, 30, 40),         # control panel
	])

static func _build_office() -> void:
	_add(&"desk", Vector2(64, 34), [
		_box(0.0, 0.0, 1.0, 1.0, 14, 16),            # top
		_seg(0.05, 0.1, 0, 0.05, 0.1, 14),           # legs
		_seg(0.95, 0.1, 0, 0.95, 0.1, 14),
		_seg(0.05, 0.9, 0, 0.05, 0.9, 14),
		_seg(0.95, 0.9, 0, 0.95, 0.9, 14),
		_box(0.35, 0.1, 0.3, 0.12, 16, 28),          # monitor
	])
	# Four desks back to back with a privacy partition down the middle.
	_add(&"desk_cluster", Vector2(140, 80), [
		_box(0.0, 0.0, 0.49, 0.46, 14, 16),
		_box(0.51, 0.0, 0.49, 0.46, 14, 16),
		_box(0.0, 0.54, 0.49, 0.46, 14, 16),
		_box(0.51, 0.54, 0.49, 0.46, 14, 16),
		_box(0.0, 0.47, 1.0, 0.06, 0, 30),           # partition
		_box(0.15, 0.36, 0.18, 0.08, 16, 26),        # monitors
		_box(0.66, 0.36, 0.18, 0.08, 16, 26),
		_box(0.15, 0.56, 0.18, 0.08, 16, 26),
		_box(0.66, 0.56, 0.18, 0.08, 16, 26),
	])
	_add(&"meeting_table", Vector2(150, 70), [
		_box(0.12, 0.2, 0.76, 0.6, 14, 16),
		_cyl(0.5, 0.5, 0.12, 0, 14),                 # pedestal
		_box(0.2, 0.0, 0.1, 0.14, 0, 12),            # chairs
		_box(0.45, 0.0, 0.1, 0.14, 0, 12),
		_box(0.7, 0.0, 0.1, 0.14, 0, 12),
		_box(0.2, 0.86, 0.1, 0.14, 0, 12),
		_box(0.45, 0.86, 0.1, 0.14, 0, 12),
		_box(0.7, 0.86, 0.1, 0.14, 0, 12),
	])
	# Glass meeting room: posts and a top rail, door gap on the -y side.
	_add(&"meeting_pod", Vector2(200, 120), [
		_seg(0.0, 0.0, 0, 0.0, 0.0, 50),
		_seg(1.0, 0.0, 0, 1.0, 0.0, 50),
		_seg(0.0, 1.0, 0, 0.0, 1.0, 50),
		_seg(1.0, 1.0, 0, 1.0, 1.0, 50),
		_seg(0.0, 1.0, 50, 1.0, 1.0, 50),
		_seg(0.0, 0.0, 50, 0.0, 1.0, 50),
		_seg(1.0, 0.0, 50, 1.0, 1.0, 50),
		_seg(0.0, 0.0, 50, 0.35, 0.0, 50),           # top rail with door gap
		_seg(0.55, 0.0, 50, 1.0, 0.0, 50),
		_seg(0.35, 0.0, 0, 0.35, 0.0, 50),
		_seg(0.55, 0.0, 0, 0.55, 0.0, 50),
		_box(0.2, 0.35, 0.6, 0.35, 14, 16),          # table
		_box(0.96, 0.25, 0.03, 0.5, 18, 40),         # wall display
	])
	_add(&"sofa", Vector2(120, 46), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 10),             # base
		_box(0.0, 0.0, 1.0, 0.3, 10, 22),            # back
		_box(0.0, 0.3, 0.1, 0.7, 10, 16),            # arms
		_box(0.9, 0.3, 0.1, 0.7, 10, 16),
	])
	_add(&"plant", Vector2(32, 32), [
		_cyl(0.5, 0.5, 0.28, 0, 10),
		_ring(0.5, 0.5, 0.45, 16),
		_ring(0.5, 0.5, 0.3, 24),
	])
	_add(&"reception", Vector2(420, 80), [
		_box(0.0, 0.35, 1.0, 0.65, 0, 26),           # counter
		_box(0.0, 0.0, 0.1, 0.35, 0, 26),            # return
		_box(0.3, 0.45, 0.12, 0.25, 26, 40),         # monitors
		_box(0.6, 0.45, 0.12, 0.25, 26, 40),
	])
	_add(&"printer", Vector2(56, 44), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 22),
		_box(0.1, 0.1, 0.6, 0.8, 22, 26),            # scanner lid
		_box(0.75, 0.15, 0.2, 0.3, 22, 25),          # control panel
		_seg(1.0, 0.25, 10, 1.2, 0.25, 12),          # output tray
		_seg(1.0, 0.75, 10, 1.2, 0.75, 12),
		_seg(1.2, 0.25, 12, 1.2, 0.75, 12),
	])
	_add(&"coffee_bar", Vector2(170, 50), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 20),             # counter
		_box(0.08, 0.15, 0.18, 0.6, 20, 36),         # espresso machine
		_cyl(0.42, 0.45, 0.12, 20, 30),              # grinder
		_ring(0.65, 0.5, 0.18, 20),                  # sink
		_box(0.8, 0.2, 0.12, 0.6, 20, 28),           # cup stack
	])
	_add(&"coffee_machine", Vector2(44, 36), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 30),
		_box(0.15, 0.6, 0.7, 0.4, 6, 8),             # drip tray
		_cyl(0.5, 0.75, 0.15, 8, 16),                # carafe
		_box(0.0, 0.0, 1.0, 0.5, 30, 36),            # hopper
	])
	_add(&"water_cooler", Vector2(24, 24), [
		_box(0.1, 0.1, 0.8, 0.8, 0, 26),
		_cyl(0.5, 0.5, 0.32, 26, 40),                # bottle
	])
	_add(&"vending_machine", Vector2(56, 40), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 58),
		_seg(0.1, 1.0, 20, 0.1, 1.0, 54),            # glass front
		_seg(0.7, 1.0, 20, 0.7, 1.0, 54),
		_seg(0.1, 1.0, 54, 0.7, 1.0, 54),
		_seg(0.1, 1.0, 20, 0.7, 1.0, 20),
		_box(0.76, 0.9, 0.16, 0.1, 30, 44),          # keypad
	])
	_add(&"conference_display", Vector2(110, 14), [
		_box(0.0, 0.2, 1.0, 0.6, 18, 52),
		_seg(0.5, 0.5, 0, 0.5, 0.5, 18),             # stand
	])
	_add(&"kiosk", Vector2(36, 30), [
		_box(0.25, 0.25, 0.5, 0.5, 0, 28),           # pedestal
		_box(0.05, 0.1, 0.9, 0.8, 28, 40),           # screen head
	])
	_add(&"filing_cabinet", Vector2(40, 30), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 36),
		_seg(0.0, 1.0, 12, 1.0, 1.0, 12),            # drawers
		_seg(0.0, 1.0, 24, 1.0, 1.0, 24),
	])

static func _build_records() -> void:
	# Rolling archive shelving: a run of mobile stacks with end handwheels.
	_add(&"filing_stacks", Vector2(200, 60), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 3),
		_box(0.0, 0.0, 0.15, 1.0, 3, 46),
		_box(0.17, 0.0, 0.15, 1.0, 3, 46),
		_box(0.34, 0.0, 0.15, 1.0, 3, 46),
		_box(0.6, 0.0, 0.15, 1.0, 3, 46),            # gap = open aisle
		_box(0.77, 0.0, 0.15, 1.0, 3, 46),
		_ring(0.075, 1.0, 0.18, 26),                 # handwheels
		_ring(0.245, 1.0, 0.18, 26),
		_ring(0.415, 1.0, 0.18, 26),
		_ring(0.675, 1.0, 0.18, 26),
		_ring(0.845, 1.0, 0.18, 26),
	])
	_add(&"scanner_station", Vector2(80, 44), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 20),
		_box(0.08, 0.15, 0.5, 0.7, 20, 28),          # scanner bed
		_box(0.7, 0.2, 0.22, 0.2, 20, 32),           # monitor
	])
	_add(&"shredder", Vector2(30, 26), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 26),
		_seg(0.2, 0.5, 26, 0.8, 0.5, 26),            # slot
	])
	_add(&"server_rack", Vector2(30, 50), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 62),
		_seg(0.0, 1.0, 16, 1.0, 1.0, 16),            # unit lines on the front
		_seg(0.0, 1.0, 30, 1.0, 1.0, 30),
		_seg(0.0, 1.0, 44, 1.0, 1.0, 44),
		_box(0.4, 0.0, 0.2, 0.15, 62, 66),           # cable drop
	])
	# Mesh partition: corner posts, top rail, vertical mesh bars on the long
	# sides, and a gate gap in the middle of the +y side.
	var cage_parts: Array = [
		_seg(0.0, 0.0, 0, 0.0, 0.0, 56),
		_seg(1.0, 0.0, 0, 1.0, 0.0, 56),
		_seg(0.0, 1.0, 0, 0.0, 1.0, 56),
		_seg(1.0, 1.0, 0, 1.0, 1.0, 56),
		_seg(0.0, 0.0, 56, 1.0, 0.0, 56),
		_seg(0.0, 0.0, 56, 0.0, 1.0, 56),
		_seg(1.0, 0.0, 56, 1.0, 1.0, 56),
		_seg(0.0, 1.0, 56, 0.4, 1.0, 56),
		_seg(0.6, 1.0, 56, 1.0, 1.0, 56),
	]
	for i in range(1, 10):
		var x := i / 10.0
		if x > 0.35 and x < 0.65:
			continue
		cage_parts.append(_seg(x, 1.0, 0, x, 1.0, 56))
	_add(&"cage", Vector2(180, 100), cage_parts)
	_add(&"vault_door", Vector2(40, 120), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 64),
		_ring(1.0, 0.5, 0.6, 32),                    # locking wheel
		_seg(1.0, 0.35, 32, 1.0, 0.65, 32),
		_box(0.0, -0.1, 1.0, 0.1, 0, 64),            # hinge block
	])

static func _build_facility() -> void:
	_add(&"lockers", Vector2(190, 80), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 56),
		_seg(0.25, 0.0, 56, 0.25, 1.0, 56),          # locker divisions (top face)
		_seg(0.5, 0.0, 56, 0.5, 1.0, 56),
		_seg(0.75, 0.0, 56, 0.75, 1.0, 56),
	])
	_add(&"decon_shower", Vector2(600, 50), [
		_box(0.0, 0.0, 0.03, 1.0, 0, 62),
		_box(0.33, 0.0, 0.03, 1.0, 0, 62),
		_box(0.66, 0.0, 0.03, 1.0, 0, 62),
		_box(0.97, 0.0, 0.03, 1.0, 0, 62),
		_seg(0.0, 0.5, 62, 1.0, 0.5, 62),            # spray bar
		_ring(0.17, 0.5, 0.25, 58),
		_ring(0.5, 0.5, 0.25, 58),
		_ring(0.83, 0.5, 0.25, 58),
	])
	_add(&"charging_rack", Vector2(720, 70), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 8),
		_box(0.02, 0.1, 0.2, 0.8, 8, 20),
		_box(0.27, 0.1, 0.2, 0.8, 8, 20),
		_box(0.52, 0.1, 0.2, 0.8, 8, 20),
		_box(0.77, 0.1, 0.2, 0.8, 8, 20),
		_seg(0.0, 0.0, 8, 0.0, 0.0, 44),
		_seg(1.0, 0.0, 8, 1.0, 0.0, 44),
		_seg(0.0, 0.0, 44, 1.0, 0.0, 44),            # gantry
	])
	_add(&"plinth", Vector2(240, 100), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 6),
		_box(0.1, 0.1, 0.8, 0.8, 6, 10),
	])
	_add(&"cleaning_bot", Vector2(36, 36), [
		_cyl(0.5, 0.5, 0.48, 0, 8),
		_ring(0.5, 0.5, 0.3, 8),
		_seg(0.5, 0.5, 8, 1.0, 0.5, 8),              # heading tick
	])

static func _build_signal_hardware() -> void:
	_add(&"coolant_valve", Vector2(130, 84), [
		_box(0.0, 0.38, 1.0, 0.24, 6, 18),           # pipe run
		_cyl(0.5, 0.5, 0.28, 0, 30),                 # valve body
		_seg(0.5, 0.5, 30, 0.5, 0.5, 44),            # stem
		_ring(0.5, 0.5, 0.42, 44),                   # handwheel
		_seg(0.29, 0.5, 44, 0.71, 0.5, 44),
		_seg(0.5, 0.29, 44, 0.5, 0.71, 44),
	])
	_add(&"nanofab", Vector2(144, 96), [
		_box(0.0, 0.1, 1.0, 0.8, 0, 36),             # cabinet
		_box(0.15, 0.25, 0.4, 0.5, 36, 50),          # hopper
		_cyl(0.78, 0.5, 0.12, 36, 46),               # extruder head
		_seg(0.0, 0.5, 8, 1.0, 0.5, 8),              # output tray lip
	])
	_add(&"breaker_panel", Vector2(124, 50), [
		_box(0.0, 0.0, 1.0, 1.0, 10, 64),
		_seg(0.5, 1.0, 10, 0.5, 1.0, 64),            # door split
		_seg(0.15, 1.0, 50, 0.85, 1.0, 50),
		_box(0.4, 0.0, 0.2, 0.3, 64, 74),            # conduit
	])
	_add(&"console", Vector2(130, 84), [
		_box(0.0, 0.3, 1.0, 0.7, 0, 24),             # desk
		_seg(0.1, 0.3, 24, 0.1, 0.1, 44),            # screen
		_seg(0.9, 0.3, 24, 0.9, 0.1, 44),
		_seg(0.1, 0.1, 44, 0.9, 0.1, 44),
		_seg(0.1, 0.3, 24, 0.9, 0.3, 24),
	])
	_add(&"interface_rig", Vector2(190, 120), [
		_box(0.0, 0.0, 1.0, 1.0, 0, 6),              # platform
		_cyl(0.5, 0.5, 0.22, 6, 40),                 # core
		_ring(0.5, 0.5, 0.42, 30),                   # halo
		_seg(0.08, 0.5, 6, 0.28, 0.5, 30),           # struts
		_seg(0.92, 0.5, 6, 0.72, 0.5, 30),
		_seg(0.5, 0.08, 6, 0.5, 0.28, 30),
	])
