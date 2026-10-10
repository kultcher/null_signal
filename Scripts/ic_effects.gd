class_name ICEffectsHost extends Control

enum RevealMode {
	ON_SCAN,
	ALWAYS
}

@onready var overlay: Control = $ICOverlay
@onready var progress: Control = $ICProgress

var _active_sig: ActiveSignal = null
var _signal_entity: Node = null
var _effect_entries: Array[Dictionary] = []

func initialize(active_sig: ActiveSignal, signal_entity: Node) -> void:
	_active_sig = active_sig
	_signal_entity = signal_entity
	set_process(true)
	sync_effect_visibility()

func _process(_delta: float) -> void:
	if _effect_entries.is_empty():
		return
	sync_effect_visibility()

func clear_effects() -> void:
	for entry in _effect_entries:
		var effect_node = entry.get("node", null) as Node
		if effect_node != null and is_instance_valid(effect_node):
			effect_node.queue_free()
	_effect_entries.clear()

func register_effect(
	effect_id: StringName,
	effect_node: CanvasItem,
	module_index: int = -1,
	reveal_mode: int = RevealMode.ON_SCAN,
	layer_name: StringName = &"overlay"
) -> CanvasItem:
	if effect_node == null:
		return null

	var parent := _get_layer_node(layer_name)
	if parent == null:
		parent = overlay
	if effect_node.get_parent() != parent:
		parent.add_child(effect_node)

	# Nest progress rings when a signal has several timed IC.
	if effect_node.has_method("set_ring_index"):
		var ring_index := 0
		for entry in _effect_entries:
			var other = entry.get("node", null)
			if other != null and is_instance_valid(other) and other.has_method("set_ring_index"):
				ring_index += 1
		effect_node.set_ring_index(ring_index)

	_effect_entries.append({
		"id": effect_id,
		"node": effect_node,
		"module_index": module_index,
		"reveal_mode": reveal_mode,
		"layer_name": layer_name,
	})
	sync_effect_visibility()
	return effect_node

func unregister_effect(effect_node: Node) -> void:
	if effect_node == null:
		return
	for i in range(_effect_entries.size() - 1, -1, -1):
		var entry = _effect_entries[i]
		if entry.get("node", null) == effect_node:
			_effect_entries.remove_at(i)
	if is_instance_valid(effect_node):
		effect_node.queue_free()

func sync_effect_visibility() -> void:
	for entry in _effect_entries:
		var effect_node = entry.get("node", null) as CanvasItem
		if effect_node == null or not is_instance_valid(effect_node):
			continue
		var is_active := true
		if effect_node.get("active") != null:
			is_active = bool(effect_node.get("active"))
		var show_when_idle := false
		if effect_node.get("show_when_idle") != null:
			show_when_idle = bool(effect_node.get("show_when_idle"))
		effect_node.visible = _should_show_entry(entry) and (is_active or show_when_idle)

func _should_show_entry(entry: Dictionary) -> bool:
	var reveal_mode := int(entry.get("reveal_mode", RevealMode.ON_SCAN))
	if reveal_mode == RevealMode.ALWAYS:
		return true
	if _active_sig == null:
		return false
	return _active_sig.is_ic_module_revealed(int(entry.get("module_index", -1)))

func _get_layer_node(layer_name: StringName) -> Control:
	match layer_name:
		&"progress":
			return progress
		_:
			return overlay
