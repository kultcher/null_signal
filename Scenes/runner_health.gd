extends MarginContainer

@onready var pip_container = $PipVbox

var pip_scene = preload("res://Scenes/health_pip.tscn")

var pips: Array[CenterContainer] = []
var max_health = 3
var current_health = 3
var _death_emitted := false

func _ready():
	GlobalEvents.runners_damaged.connect(_take_damage)
	for i in 3:
		var pip = pip_scene.instantiate()
		pip_container.add_child(pip)
		pips.append(pip)
	_refresh_pips()

func reset_health() -> void:
	current_health = max_health
	_death_emitted = false
	_refresh_pips()

func _take_damage(amount: float):
	if _death_emitted:
		return
	var damage := maxi(1, int(round(amount)))
	current_health = maxi(0, current_health - damage)
	_refresh_pips()
	if current_health <= 0:
		_death_emitted = true
		GlobalEvents.runner_died.emit()

func _refresh_pips() -> void:
	for i in pips.size():
		var pip_fill := pips[i].get_child(1)
		if pip_fill == null:
			continue
		pip_fill.visible = i < current_health
