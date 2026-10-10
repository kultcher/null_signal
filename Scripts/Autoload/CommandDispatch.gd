# Autoload: CommandDispatch.gd
# Receives terminal commands and routes responses back to terminal, timeline, signals, etc.

extends Node

var timeline_manager: Node2D = null
var signal_manager: Node2D = null
var terminal_window: Control = null

var window_manager: CanvasLayer = null

func clear_run_references() -> void:
	timeline_manager = null
	signal_manager = null
	terminal_window = null
	window_manager = null

# === SIGNALS ===
signal set_terminal_signal(active_sig: ActiveSignal)
signal command_complete(cmd_context: CommandContext)
signal command_error(error_msg: String, context: ActiveSignal)

# === COMMAND REGISTRY ===
const VALID_COMMANDS = {
	"ACCESS": {
		"valid_flags": ["-bp"],
		"description": "Access: Access a system"
	},
	"PROBE": {
		"valid_flags": [],
		"description": "Inspect: Inspect a system"
	},
	"SPOOF": {
		"valid_flags": [],
		"description": "Spoof: Deceive a system"
	},
	"KILL": {
		"valid_flags": [],
		"description": "Kill: Disable a system"
	},
	"RUN": {
		"valid_flags": ["-dc", "-ms", "-nl"],
		"description": "Run: Run a local program"
	},
	"OP": {
		"valid_flags": [],
		"description": "Operate: Do the thing."
	},
	"HELP": {
		"valid_flags": [],
		"description": "Help: Display help panel."
	}
}

const COMMAND_SHORTCUTS = {
	"ACC": "ACCESS",
	"INS": "PROBE",
	"SPF": "SPOOF",
	"KIL": "KILL",
	"PRB": "PROBE",
	"LNK": "LINK"
}

const ROOT_CONTEXT_ERROR := "Not applicable on ROOT, connect to a session."

func switch_terminal_session(active_sig: ActiveSignal, show_connection_banner: bool = false):
	if active_sig == null:
		return
	if not GlobalEvents.is_tutorial_feature_enabled("connect"):
		return
	GlobalEvents.signal_connect.emit(active_sig.data)
	terminal_window.switch_session(active_sig, show_connection_banner)

# === MAIN ENTRY POINT ===

func process_command(input: String, active_sig: ActiveSignal = null) -> void:
	if not GlobalEvents.is_tutorial_feature_enabled("terminal_commands"):
		_fail("[b][color=red]SEQUENCE BREAK[/color][/b]: unexpected signal degradation.\nBuffering... [color=cyan]close external communcations[/color] and try again.", active_sig)
		return
	if _try_special_command(input, active_sig):
		return
	if _try_callback_input(input, active_sig):
		return
	var parsed = parse_input(input)
	if parsed.has("error"):
		_fail(parsed.error, active_sig)
		return

	var cmd_context := CommandContext.new()
	cmd_context.command = parsed.command
	cmd_context.flags = parsed.flags
	cmd_context.arg = parsed.args[0] if not parsed.args.is_empty() else ""
	cmd_context.active_sig = active_sig

	var usage_error := _validate_command_usage(cmd_context.command, parsed.args)
	if usage_error != "":
		_fail(usage_error, active_sig)
		return

	var resolved := _resolve_command_context(cmd_context)
	if resolved.has("error"):
		_fail(resolved.error, active_sig)
		return

	# Commands with an explicit target (KILL cam_02) also move the terminal to
	# that signal's session. That switch happens only after the action
	# resolves, so IC can veto it, and errors are reported in the session the
	# player typed into rather than one they never reached.
	var switch_target: ActiveSignal = null
	if resolved.has("switch_target"):
		switch_target = resolved.switch_target
		cmd_context.active_sig = switch_target

	if cmd_context.command != "RUN" and cmd_context.command != "ACCESS" and _is_puzzle_locked(cmd_context.active_sig):
		_fail("ACCESS DENIED", active_sig)
		return

	_try_command(cmd_context, active_sig, switch_target)

# === PARSER ===

func parse_input(input: String) -> Dictionary:
	var result = {
		"command": "",
		"args": [],
		"flags": []
	}

	var trimmed = input.strip_edges()
	if trimmed.is_empty():
		return {"error": "No command entered"}

	var parts = trimmed.split(" ", false)
	var cmd = parts[0].to_upper()

	if cmd in COMMAND_SHORTCUTS:
		cmd = COMMAND_SHORTCUTS[cmd]

	if not cmd in VALID_COMMANDS:
		return {"error": "Unknown command: " + cmd}

	result.command = cmd

	for i in range(1, parts.size()):
		var part = parts[i]
		if part.begins_with("-"):
			result.flags.append(part)
		else:
			result.args.append(part.to_lower())

	return result

# === VALIDATION ===

func _validate_command_usage(command: String, args: Array) -> String:
	var arg_count = args.size()

	match command:
		"ACCESS":
			if arg_count <= 0:
				return "ACC requires a target"
			if arg_count > 1:
				return "ACCESS takes exactly one target"
		"RUN":
			if arg_count <= 0:
				return "RUN requires a program name"
			if arg_count > 1:
				return "RUN takes exactly one program name"
		"KILL", "OP", "PROBE":
			if arg_count > 1:
				return command + " takes at most one target"
		"SPOOF":
			if arg_count <= 0:
				return "SPOOF requires an explicit target"
			if arg_count > 1:
				return "SPOOF takes exactly one target"
		"HELP":
			if arg_count > 0:
				return "HELP takes no arguments"

	return ""

func _resolve_command_context(cmd_context: CommandContext) -> Dictionary:
	var has_explicit_arg := not cmd_context.arg.is_empty()
	var session_sig: ActiveSignal = terminal_window.active_signal
	var using_root := _is_root_session(session_sig)

	match cmd_context.command:
		"ACCESS":
			var access_target := _resolve_signal_target(cmd_context.arg)
			if access_target.has("error"):
				return access_target
			return {"switch_target": access_target.signal}

		"RUN":
			if using_root:
				return {"error": ROOT_CONTEXT_ERROR}
			cmd_context.active_sig = session_sig
			return {}

		"KILL", "OP", "PROBE":
			if has_explicit_arg:
				var command_target := _resolve_signal_target(cmd_context.arg)
				if command_target.has("error"):
					return command_target
				return {
					"switch_target": command_target.signal
				}
			if using_root:
				return {"error": ROOT_CONTEXT_ERROR}
			cmd_context.active_sig = session_sig
			return {}

		"SPOOF":
			return {"error": "SPOOF not yet implemented"}

	return {}

func _resolve_signal_target(system_id: String) -> Dictionary:
	if signal_manager == null:
		return {"error": "Signal manager unavailable"}
	if not signal_manager.has_signal_in_network(system_id):
		return {"error": "No such signal in network"}
	if not signal_manager.is_signal_in_range(system_id):
		return {"error": system_id + ": signal not in range"}

	var sig: ActiveSignal = signal_manager.get_signal_by_system_id(system_id)
	if sig == null:
		return {"error": "No such signal in network"}
	return {"signal": sig}

func _is_root_session(active_sig: ActiveSignal) -> bool:
	return terminal_window != null and active_sig == terminal_window.root_signal

func _is_puzzle_locked(active_sig: ActiveSignal) -> bool:
	if active_sig == null or active_sig.data == null:
		return false
	if active_sig.data.puzzle == null:
		return false
	return active_sig.data.puzzle.puzzle_locked

func _fail(error_msg: String, context: ActiveSignal) -> void:
	command_error.emit(error_msg, context)

func _try_special_command(input: String, active_sig: ActiveSignal) -> bool:
	var trimmed := input.strip_edges()
	if trimmed.to_upper() != "INTERFACE NS_01A.SYS -U -C":
		return false

	var cmd_context := CommandContext.new()
	cmd_context.active_sig = active_sig
	cmd_context.command = "INTERFACE"
	cmd_context.log_text.append("NULL SPIKE INTERFACE STAGED")
	GlobalEvents.null_spike_init.emit()
	_finalize_command(cmd_context)
	return true

func _try_callback_input(input: String, active_sig: ActiveSignal) -> bool:
	var trimmed := input.strip_edges()
	if not trimmed.begins_with("$"):
		return false
	if active_sig == null or _is_root_session(active_sig):
		_fail(ROOT_CONTEXT_ERROR, active_sig)
		return true

	var callback_value := trimmed.substr(1).strip_edges()
	if callback_value.is_empty():
		_fail("Callback sequence required after $.", active_sig)
		return true

	var cmd_context := CommandContext.new()
	cmd_context.active_sig = active_sig
	cmd_context.command = "CALLBACK"
	cmd_context.arg = callback_value
	_try_command(cmd_context)
	return true

# origin_sig: the session the command was typed in (where errors go).
# switch_target: session to move to once the command succeeds.
func _try_command(cmd_context: CommandContext, origin_sig: ActiveSignal = null, switch_target: ActiveSignal = null) -> void:
	print("Command Dispatch trying command: " + cmd_context.command)
	if origin_sig == null:
		origin_sig = cmd_context.active_sig
	var action_context := ActionResolver.build_action_from_command(cmd_context)
	ActionResolver.resolve_action(action_context)
	var failed := cmd_context.status == CommandContext.CommandStatus.FAILURE
	if not failed and switch_target != null and cmd_context.command != "ACCESS":
		switch_terminal_session(switch_target, false)
	_finalize_command(cmd_context, origin_sig if failed else null)

func _finalize_command(cmd_context: CommandContext, error_sig: ActiveSignal = null):
	if cmd_context.status == CommandContext.CommandStatus.FAILURE:
		if not cmd_context.log_text.is_empty():
			_fail(cmd_context.log_text[0], error_sig if error_sig != null else cmd_context.active_sig)
		return
	print("Command Dispatch finished command: " + cmd_context.command)
	command_complete.emit(cmd_context)
