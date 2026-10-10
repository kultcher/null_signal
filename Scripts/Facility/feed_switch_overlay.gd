# feed_switch_overlay.gd
# Relay remap transition over the facility map when the runner moves into a
# new section. In the fiction the player isn't watching cameras: the runner's
# relay maps the surrounding device mesh and streams that picture back. When
# the runner leaves mapped space (a stairwell, an elevator, a thick wall) the
# relay loses the mesh, then rebuilds the new area: a scan line sweeps out
# from the runner and the map is painted in behind it.

extends Node2D

const BLACKOUT := 0.25            # link dropped, nothing mapped yet
const SWEEP := 0.55               # scan line paints the new area
const HOLD := 0.35                # zone label lingers after the sweep
const DURATION := BLACKOUT + SWEEP + HOLD
const STATIC_LINES := 18
const SCAN_COLOR := Color(0.0, 0.85, 1.0, 0.9)
const TEXT_COLOR := Color(0.0, 0.85, 1.0, 0.9)

@onready var timeline_manager = $"../TimelineManager"

var _font: Font = preload("res://Visuals/Fonts/ShareTechMono-Regular.ttf")
var _t := -1.0
var _label := ""
var _sweep_origin_x := 0.0

func _ready() -> void:
	# Above signal tooltips (z 200) so the whole map drops out.
	z_index = 300
	timeline_manager.section_changed.connect(_on_section_changed)
	set_process(false)

static func zone_label(index: int, section: FacilitySection) -> String:
	return "MESH %02d // %s" % [index + 1, section.label]

func _on_section_changed(section: FacilitySection) -> void:
	if not timeline_manager.map_mode:
		return
	var sections: Array[FacilitySection] = timeline_manager.facility_layout.sections
	_label = zone_label(sections.find(section), section)
	_sweep_origin_x = clampf(timeline_manager.get_runner_screen_pos().x, 0.0, timeline_manager.screen_width)
	_t = 0.0
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION:
		_t = -1.0
		set_process(false)
	queue_redraw()

func _draw() -> void:
	if _t < 0.0:
		return
	var rect: Rect2 = timeline_manager.get_map_rect()
	var center := rect.get_center() + Vector2(-260.0, 8.0)

	if _t < BLACKOUT:
		# Link dropped: dark map with a little interference.
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.94), true)
		for i in STATIC_LINES:
			var y := rect.position.y + randf() * rect.size.y
			var x := randf() * rect.size.x * 0.6
			var w := randf_range(rect.size.x * 0.15, rect.size.x * 0.7)
			draw_rect(Rect2(x, y, w, randf_range(1.0, 4.0)), Color(0.0, 0.85, 1.0, randf_range(0.03, 0.15)), true)
		draw_string(_font, center, "RELAY LINK DROPPED // RESCANNING LOCAL MESH", HORIZONTAL_ALIGNMENT_CENTER, 520.0, 22, TEXT_COLOR)
		return

	var sweep_t := clampf((_t - BLACKOUT) / SWEEP, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - sweep_t, 2.0)
	if sweep_t < 1.0:
		# Unmapped space ahead of (and behind) the scan front stays dark.
		var reach := eased * maxf(rect.end.x - _sweep_origin_x, _sweep_origin_x - rect.position.x)
		var left := maxf(rect.position.x, _sweep_origin_x - reach)
		var right := minf(rect.end.x, _sweep_origin_x + reach)
		if left > rect.position.x:
			draw_rect(Rect2(rect.position.x, rect.position.y, left - rect.position.x, rect.size.y), Color(0, 0, 0, 0.94), true)
		if right < rect.end.x:
			draw_rect(Rect2(right, rect.position.y, rect.end.x - right, rect.size.y), Color(0, 0, 0, 0.94), true)
		# Scan front(s): bright line with a soft trailing glow.
		for front_x in [left, right]:
			if front_x <= rect.position.x + 1.0 or front_x >= rect.end.x - 1.0:
				continue
			var trail_dir := 1.0 if front_x < _sweep_origin_x else -1.0
			for g in 6:
				var gx: float = front_x + trail_dir * g * 6.0
				draw_line(Vector2(gx, rect.position.y), Vector2(gx, rect.end.y), Color(SCAN_COLOR, 0.25 - g * 0.04), 6.0)
			draw_line(Vector2(front_x, rect.position.y), Vector2(front_x, rect.end.y), SCAN_COLOR, 2.0)

	var fade := 1.0 if _t < BLACKOUT + SWEEP else 1.0 - (_t - BLACKOUT - SWEEP) / HOLD
	var label_bg := Rect2(center + Vector2(40.0, -26.0), Vector2(440.0, 36.0))
	draw_rect(label_bg, Color(0, 0, 0, 0.75 * fade), true)
	draw_string(_font, center, "MAPPED // " + _label, HORIZONTAL_ALIGNMENT_CENTER, 520.0, 22, Color(TEXT_COLOR, TEXT_COLOR.a * fade))
