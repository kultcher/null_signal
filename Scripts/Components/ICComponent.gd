# ICComponent.gd
# Component for adding IC protection to Signals

class_name ICComponent extends Resource

@export var modules: Array[Resource] = [] # Array of ICModule resources

func get_desc():
	var formatted: String = ""
	var module_info = []
	for module in modules:
		module_info.append(module.get_desc())
	if module_info.size() == 0:
		return "None"
	else:
		for info in module_info:
			if info == module_info[-1]:
				formatted += info
			else:
				formatted += info + " | "
	return formatted

func add_module(module: Resource):
	modules.append(module)

func process_action(action_context: ActionContext) -> void:
	for module in modules:
		if module == null:
			continue
		module.process_action(action_context)

func postprocess_action(action_context: ActionContext) -> void:
	for module in modules:
		if module == null:
			continue
		module.postprocess_action(action_context)

# Actions aimed at *other* signals while this signal has an open session.
func process_external_action(action_context: ActionContext, host_sig: ActiveSignal) -> void:
	for module in modules:
		if module == null:
			continue
		module.process_external_action(action_context, host_sig)

func postprocess_external_action(action_context: ActionContext, host_sig: ActiveSignal) -> void:
	for module in modules:
		if module == null:
			continue
		module.postprocess_external_action(action_context, host_sig)

func notify_connected(active_sig: ActiveSignal):
	for module in modules:
		module.on_connect(active_sig)

func notify_initialized(active_sig: ActiveSignal):
	for module in modules:
		module.on_initialized(active_sig)

func notify_session_closed(active_sig: ActiveSignal):
	for module in modules:
		module.on_session_closed(active_sig)

func notify_enabled(active_sig: ActiveSignal):
	for module in modules:
		module.on_enabled(active_sig)

func notify_disabled(active_sig: ActiveSignal):
	for module in modules:
		module.on_disabled(active_sig)

func notify_visuals_ready(active_sig: ActiveSignal, ic_effects: ICEffectsHost) -> void:
	for i in range(modules.size()):
		var module = modules[i]
		if module == null:
			continue
		module.on_visuals_ready(active_sig, ic_effects, i)

func notify_visuals_cleared(active_sig: ActiveSignal) -> void:
	for module in modules:
		if module == null:
			continue
		module.on_visuals_cleared(active_sig)

func get_connection_flow_lines(active_sig: ActiveSignal) -> Array[String]:
	var lines: Array[String] = []
	for module in modules:
		if module == null:
			continue
		lines.append_array(module.get_connection_flow_lines(active_sig))
	return lines
