# EncounterTemplate.gd
# A reusable obstacle group: mostly fixed elements plus (optionally) one
# wildcard element whose behavior or position varies per placement. Templates
# are Resources so tuned variants can be saved as .tres; subclasses implement
# _build(). See DesignNotes/EncounterTemplates.md.
#
# Coordinates are relative to an anchor cell on a straight stretch of route at
# `route_lane`. Lanes 0..4 are the standard hall; `flipped` mirrors top/bottom.
class_name EncounterTemplate extends Resource

const CELL_PX := 240.0
const LANE_PX := 90.0
const FIT_STEP := 0.25
const ROUTE_TOLERANCE := 0.3

@export var template_id: StringName = &"encounter"
@export var display_name := "Encounter"
@export_range(1, 5, 1) var difficulty := 1
@export var route_lane := 2
# Lanes that must be inside a room across the whole footprint.
@export var required_lanes: PackedInt32Array = PackedInt32Array([0, 2, 4])
# Free-form tags for the generator: "transition", "watchers", "patrol", ...
@export var tags: PackedStringArray = PackedStringArray()
# Allow random top/bottom mirroring.
@export var allow_flip := true

# Generates one placement. `rng` drives every random choice, so the same seed
# reproduces the same encounter. `prefix` makes system ids unique.
func generate(run: RunDefinition, anchor_cell: float, rng: RandomNumberGenerator, prefix: String = "") -> EncounterInstance:
	var inst := EncounterInstance.new()
	inst.template_id = template_id
	inst.label = display_name.to_upper()
	inst.prefix = prefix if not prefix.is_empty() else String(template_id)
	inst.anchor_cell = anchor_cell
	inst.start_cell = anchor_cell
	inst.end_cell = anchor_cell + get_base_length()
	inst.route_lane = route_lane
	inst.flipped = allow_flip and rng.randf() < 0.5
	_build(run, inst, rng)
	return inst

# Length without the wildcard; _build may extend inst.end_cell.
func get_base_length() -> float:
	return 4.0

# Upper bound on the footprint, for planning space before generating.
func get_max_length() -> float:
	return get_base_length()

func _build(_run: RunDefinition, _inst: EncounterInstance, _rng: RandomNumberGenerator) -> void:
	push_error("EncounterTemplate._build() not implemented for %s" % template_id)

# --- fit ---

# Checks that the layout can host this template from anchor_cell over
# `length` cells: a straight route at route_lane inside one section (unless
# tagged "transition"), with every required lane inside a room. Returns a list
# of problems; empty means it fits.
func check_fit(layout: FacilityLayout, anchor_cell: float, length: float = -1.0) -> PackedStringArray:
	var issues := PackedStringArray()
	if length < 0.0:
		length = get_max_length()
	var end := anchor_cell + length
	var first_section: FacilitySection = layout.get_section_for_cell(anchor_cell)
	var cell := anchor_cell
	while cell <= end + 0.0001:
		var section: FacilitySection = layout.get_section_for_cell(cell)
		if section != first_section and not tags.has("transition"):
			issues.append("crosses into section %s at cell %.2f" % [section.id, cell])
			break
		var lane := layout.sample_position(layout.progress_at_cell(cell)).y
		if absf(lane - route_lane) > ROUTE_TOLERANCE:
			issues.append("route at lane %.2f, not %d, at cell %.2f" % [lane, route_lane, cell])
			break
		if layout.has_rooms():
			for required in required_lanes:
				if layout.get_room_at(cell, float(required)) == null:
					issues.append("lane %d outside any room at cell %.2f" % [required, cell])
					return issues
		cell += FIT_STEP
	return issues

# --- helpers for subclasses ---

# Lane after optional top/bottom mirroring around the 0..4 hall.
func lane_of(inst: EncounterInstance, lane: int) -> int:
	return 4 - lane if inst.flipped else lane

# Patrol/route lane offsets flip sign when mirrored.
func lane_offset(inst: EncounterInstance, offset: float) -> float:
	return -offset if inst.flipped else offset

# Cone facings mirror as f -> -f (cones look along (-cos f, -sin f)).
func cone_facing(inst: EncounterInstance, facing_deg: float) -> float:
	return -facing_deg if inst.flipped else facing_deg

# Facing that points a cone from `from` toward `to` (cell, lane).
static func cone_facing_toward(from: Vector2, to: Vector2) -> float:
	var d := Vector2((to.x - from.x) * CELL_PX, (to.y - from.y) * LANE_PX)
	return rad_to_deg(atan2(-d.y, -d.x))

static func distance_cells(from: Vector2, to: Vector2) -> float:
	return Vector2((to.x - from.x) * CELL_PX, (to.y - from.y) * LANE_PX).length() / CELL_PX

# Flips patrol points ([cell, lane, dwell, facing] offsets) for a mirrored
# placement.
func patrol_points(inst: EncounterInstance, points: Array) -> Array:
	var result: Array = []
	for p in points:
		var point: Array[float] = [float(p[0]), lane_offset(inst, float(p[1])), float(p[2]), float(p[3])]
		result.append(point)
	return result

# SpawnBuilder.patrol() takes up to four typed points.
static func apply_patrol(builder: RunDefinition.SpawnBuilder, points: Array) -> RunDefinition.SpawnBuilder:
	var empty: Array[float] = []
	return builder.patrol(points[0], points[1], points[2] if points.size() > 2 else empty, points[3] if points.size() > 3 else empty)
