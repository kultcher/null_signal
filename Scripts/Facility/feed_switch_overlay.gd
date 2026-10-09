# feed_switch_overlay.gd
# Brief "camera feed switch" glitch over the facility map when the runner
# moves into a new section: the feed drops to static, then reacquires on the
# new view.

extends Node2D

const DURATION := 0.7
const BLACKOUT := 0.22
const STATIC_LINES := 26
const TEXT_COLOR := Color(0.0, 0.85, 1.0, 0.9)

@onready var timeline_manager = $"../TimelineManager"

var _font: Font = preload("res://Visuals/Fonts/ShareTechMono-Regular.ttf")
var _t := -1.0
var _label := ""

func _ready() -> void:
	# Above signal tooltips (z 200) so the whole feed drops out.
	z_index = 300
	timeline_manager.section_changed.connect(_on_section_changed)
	set_process(false)

func _on_section_changed(section: FacilitySection) -> void:
	if not timeline_manager.map_mode:
		return
	var sections: Array[FacilitySection] = timeline_manager.facility_layout.sections
	_label = "FEED %02d // %s" % [sections.find(section) + 1, section.label]
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
	var fade := 1.0 if _t < BLACKOUT else 1.0 - ((_t - BLACKOUT) / (DURATION - BLACKOUT))
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.92 * fade), true)

	# Horizontal static bands.
	for i in STATIC_LINES:
		var y := rect.position.y + randf() * rect.size.y
		var h := randf_range(1.0, 6.0)
		var x := randf() * rect.size.x * 0.6
		var w := randf_range(rect.size.x * 0.2, rect.size.x)
		draw_rect(Rect2(x, y, w, h), Color(0.0, 0.85, 1.0, randf_range(0.04, 0.22) * fade), true)

	var text := "FEED LOST // REACQUIRING..." if _t < BLACKOUT else _label
	var pos := rect.get_center() + Vector2(-220.0, 8.0)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 440.0, 22, Color(TEXT_COLOR, TEXT_COLOR.a * fade))
