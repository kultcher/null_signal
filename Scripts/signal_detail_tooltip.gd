extends PanelContainer


@onready var tooltip_hbox = $TooltipHbox
@onready var tt_header = $TooltipHbox/TooltipVBox/HeaderPanel/MarginContainer/HeaderText
@onready var tt_body_control = $BodyControl
@onready var tt_body_box = $BodyControl/BodyPanel
@onready var tt_body = $BodyControl/BodyPanel/BodyText
@onready var tt_active_scan = $TooltipHbox/TooltipVBox/IconsHBox/ActiveScanPanel
@onready var tt_scan_icon = $TooltipHbox/TooltipVBox/IconsHBox/ActiveScanPanel/ScanMargin/ActiveScanIcon
@onready var tt_lock_state = $TooltipHbox/TooltipVBox/IconsHBox/LockStatePanel
@onready var tt_lock_icon = $TooltipHbox/TooltipVBox/IconsHBox/LockStatePanel/LockMargin/LockStateIcon
@onready var tt_ic_icon = $TooltipHbox/TooltipVBox/IconsHBox/ICStatePanel/ICMargin/ICStateIcon


const COLOR_STATUS_UNKNOWN := Color("4a2d64")
const COLOR_STATUS_SCANNING := Color("009632ff")
const COLOR_STATUS_COMPLETE := Color("00fa64ff")
const COLOR_STATUS_PARTIAL := Color("c1a126")

const COLOR_LOCK_OPEN := Color("0096faff")
const COLOR_LOCK_LOCKED := Color("ff0000ff")
const COLOR_LOCK_HACKED := Color("0096faff")

var _body_fade_tween: Tween = null
var _default_icon_states: Dictionary = {}

func _ready() -> void:
	for icon in [tt_scan_icon, tt_lock_icon, tt_ic_icon]:
		_default_icon_states[icon] = [icon.texture, icon.self_modulate]
	tt_body_box.resized.connect(_queue_realign_body)
	tt_body.resized.connect(_queue_realign_body)
	tooltip_hbox.resized.connect(_queue_realign_body)
	call_deferred("_align_body_panel")

func set_tooltip_collapsed(collapsed: bool):
	_stop_body_fade()
	tt_body_control.visible = not collapsed
	tt_body_box.visible = not collapsed
	tt_body.visible = not collapsed
	tt_body_box.modulate.a = 1.0 if not collapsed else 0.0
	tt_active_scan.visible = true
	tt_lock_state.visible = true
	if not collapsed:
		_queue_realign_body()

func show_body() -> void:
	_stop_body_fade()
	tt_body_control.visible = true
	tt_body_box.visible = true
	tt_body.visible = true
	tt_body_box.modulate.a = 1.0
	_queue_realign_body()

func fade_body_out(duration: float = 10.0) -> void:
	if not tt_body_box.visible:
		return
	_stop_body_fade()
	_body_fade_tween = create_tween()
	_body_fade_tween.tween_property(tt_body_box, "modulate:a", 0.0, duration)
	_body_fade_tween.finished.connect(_on_body_fade_finished, CONNECT_ONE_SHOT)

func _stop_body_fade() -> void:
	if _body_fade_tween != null and _body_fade_tween.is_valid():
		_body_fade_tween.kill()
	_body_fade_tween = null

func _on_body_fade_finished() -> void:
	_body_fade_tween = null
	tt_body_control.visible = false
	tt_body_box.visible = false
	tt_body.visible = false
	tt_body_box.modulate.a = 1.0

func _queue_realign_body() -> void:
	call_deferred("_align_body_panel")

func _align_body_panel() -> void:
	if tt_body_box == null or tooltip_hbox == null:
		return

	var target_width = tooltip_hbox.size.x
	var body_width = tt_body_box.size.x
	if target_width <= 0.0 or body_width <= 0.0:
		return

	tt_body_box.position.x = round((target_width - body_width) * 0.5)

func get_lock_state_focus_rect() -> Rect2:
	if tt_lock_state == null or not tt_lock_state.is_visible_in_tree():
		return Rect2()
	return tt_lock_state.get_global_rect()

enum IconState { UNKNOWN_SCAN, UNKNOWN_LOCK, SCANNING, PARTIAL, COMPLETE, OPEN, LOCKED, HACKED, NO_IC, ACTIVE_IC }

# Back to the unscanned look (used when IC wipes revealed scan data).
func reset_panels() -> void:
	for icon in _default_icon_states:
		var state: Array = _default_icon_states[icon]
		icon.texture = state[0]
		icon.self_modulate = state[1]

func set_panel_state(icon: Control, type):
#	var base_style = panel.get_theme_stylebox("panel")
#	var style: StyleBoxFlat
#	if base_style is StyleBoxFlat:
#		style = (base_style as StyleBoxFlat).duplicate()
#	else:
#		style = StyleBoxFlat.new()
#	panel.add_theme_stylebox_override("panel", style)
	match type:
		#IconState.UNKNOWN_SCAN:
			#icon.set_self_modulate(COLOR_STATUS_UNKNOWN)
		#IconState.UNKNOWN_LOCK:
			#icon.set_self_modulate(COLOR_STATUS_UNKNOWN)
		IconState.SCANNING:	
			icon.set_self_modulate(COLOR_STATUS_SCANNING)
		IconState.PARTIAL: icon.set_self_modulate(COLOR_STATUS_PARTIAL)
		IconState.COMPLETE:
			icon.texture = preload("res://Visuals/Icons/Simple/check-mark.svg")
			icon.set_self_modulate(COLOR_STATUS_COMPLETE)
		IconState.OPEN:
			icon.texture = preload("res://Visuals/Icons/Simple/padlock-open.svg")
			icon.set_self_modulate(COLOR_LOCK_OPEN)
		IconState.LOCKED:
			icon.texture = preload("res://Visuals/Icons/Simple/padlock.svg")
			icon.set_self_modulate(COLOR_LOCK_LOCKED)
		IconState.HACKED:
			icon.texture = preload("res://Visuals/Icons/Simple/padlock-open.svg")
			icon.set_self_modulate(COLOR_LOCK_HACKED)
		IconState.ACTIVE_IC:
			icon.set_self_modulate(COLOR_LOCK_LOCKED)
		IconState.NO_IC:
			icon.texture = preload("res://Visuals/Icons/Simple/cancel.svg")
			icon.set_self_modulate(COLOR_STATUS_COMPLETE)
