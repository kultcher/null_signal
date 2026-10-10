class_name Jargonizer extends Resource

const LINE_BANK_PATH := "res://Resources/Jargonizer/jargonizer_lines.json"
const SECTION_GENERIC := "generic"
const SECTION_CORP_SPECIFIC := "corp_specific"
const STATUS_LINE_COUNT := 3

enum PuzzleDisclosure { LOCK_ONLY, PROGRAM_ONLY, FULL }

const PUZZLE_DISCLOSURE_WEIGHTS := {
	0: {
		PuzzleDisclosure.FULL: 1.0
	},
	1: {
		PuzzleDisclosure.FULL: 0.70,
		PuzzleDisclosure.PROGRAM_ONLY: 0.20,
		PuzzleDisclosure.LOCK_ONLY: 0.10
	},
	2: {
		PuzzleDisclosure.FULL: 0.45,
		PuzzleDisclosure.PROGRAM_ONLY: 0.35,
		PuzzleDisclosure.LOCK_ONLY: 0.20
	},
	3: {
		PuzzleDisclosure.FULL: 0.20,
		PuzzleDisclosure.PROGRAM_ONLY: 0.35,
		PuzzleDisclosure.LOCK_ONLY: 0.45
	}
}

static var _line_bank_cache: Dictionary = {}

static func get_handshake(corp_id: String = "") -> String:
	return get_random_line("handshake", corp_id)

static func build_connection_flow(active_sig: ActiveSignal, corp_id: String = "") -> Array[String]:
	var lines: Array[String] = []
	if active_sig == null or active_sig.data == null:
		lines.append(get_handshake(corp_id))
		lines.append("[SESSION: unknown - unknown device]")
		lines.append("STATUS: UNKNOWN")
		return lines

	var used_lines: Dictionary = {}
	var handshake_count := 2
	for _i in range(handshake_count):
		var handshake := _pick_unique_line("handshake", used_lines, corp_id)
		if not handshake.is_empty():
			lines.append(handshake)

	lines.append("")
	lines.append(_build_session_line(active_sig))

	for status_line in _build_status_block(active_sig, corp_id):
		lines.append(status_line)

	for puzzle_line in _build_puzzle_hint_block(active_sig):
		lines.append(puzzle_line)

	for ic_line in _build_ic_connection_block(active_sig):
		lines.append(ic_line)

	#lines.append(_build_installed_line(active_sig))
	return lines

static func get_random_line(category: String, corp_id: String = "") -> String:
	var lines := get_lines(category, corp_id)
	if lines.is_empty():
		return ""
	return lines.pick_random()

static func get_lines(category: String, corp_id: String = "") -> Array[String]:
	var bank := _get_line_bank()
	var resolved: Array[String] = []

	if not corp_id.is_empty():
		resolved.append_array(_extract_corp_lines(bank, corp_id, category))

	if resolved.is_empty():
		resolved.append_array(_extract_generic_lines(bank, category))

	return resolved

static func reload_line_bank() -> void:
	_line_bank_cache.clear()

static func _get_line_bank() -> Dictionary:
	if _line_bank_cache.is_empty():
		_line_bank_cache = _load_line_bank()
	return _line_bank_cache

static func _load_line_bank() -> Dictionary:
	var file := FileAccess.open(LINE_BANK_PATH, FileAccess.READ)
	if file == null:
		push_warning("Jargonizer: could not open line bank at %s. Using fallback data." % LINE_BANK_PATH)
		return _build_fallback_bank()

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Jargonizer: invalid JSON structure in %s. Using fallback data." % LINE_BANK_PATH)
		return _build_fallback_bank()

	var bank: Dictionary = parsed
	if not bank.has(SECTION_GENERIC):
		bank[SECTION_GENERIC] = {}
	if not bank.has(SECTION_CORP_SPECIFIC):
		bank[SECTION_CORP_SPECIFIC] = {}
	return bank

static func _extract_generic_lines(bank: Dictionary, category: String) -> Array[String]:
	var generic_section = bank.get(SECTION_GENERIC, {})
	if typeof(generic_section) != TYPE_DICTIONARY:
		return []
	return _coerce_string_array(generic_section.get(category, []))

static func _extract_corp_lines(bank: Dictionary, corp_id: String, category: String) -> Array[String]:
	var corp_section = bank.get(SECTION_CORP_SPECIFIC, {})
	if typeof(corp_section) != TYPE_DICTIONARY:
		return []

	var corp_bank = corp_section.get(corp_id, {})
	if typeof(corp_bank) != TYPE_DICTIONARY:
		return []

	return _coerce_string_array(corp_bank.get(category, []))

static func _coerce_string_array(value) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return out

	for entry in value:
		if entry is String:
			out.append(entry)

	return out

static func _build_fallback_bank() -> Dictionary:
	return {
		SECTION_GENERIC: {
			"handshake": [
				"Establishing tunnel... OK",
				"Negotiating session... OK",
				"Handshake: SYN > SYN-ACK > ACK (##ms)",
				"Routing through proxy chain... 3 hops... connected.",
				"Port scan: ##/tcp open. Establishing link.",
				"Spoofing MAC address... accepted.",
				"TLS downgrade... success. Channel open.",
				"Connecting via relay ####... latency ##ms... OK",
				"Session key exchanged. Encrypted channel active.",
				"Piggyback on maintenance port... accepted.",
				"Auth bypass: null credential injection... OK",
				"Certificate pinning disabled. Proceeding.",
				"Tunneling through ####:##... connected."
			],
			"status_universal": [
				"STATUS: ONLINE",
				"UPTIME: ####h ##m",
				"FIRMWARE: v#.#.#",
				"LAST MAINT: ####-##-##",
				"NETWORK: secure_subnet",
				"POWER: MAINS",
				"ASSET TAG: LOCAL-########"
			],
			"status_camera": [
				"RECORDING: ACTIVE - buffer at ##%",
				"FEED: LIVE",
				"RESOLUTION: 1080p",
				"NIGHT VISION: AUTO",
				"MOTION DETECT: ENABLED",
				"PAN CYCLE: ##s"
			],
			"status_door": [
				"STATE: LOCKED",
				"BOLT TYPE: ELECTROMAGNETIC",
				"AUTH: Tier 2 clearance required",
				"FIRE PROTOCOL: FAIL-SECURE"
			],
			"status_drone": [
				"PATROL STATUS: ACTIVE",
				"BATTERY: ##%",
				"ALTITUDE: ##m",
				"ROUTE: STANDARD"
			],
			"status_guard": [
				"BIOMETRIC LINK: LIVE",
				"COMMS: ENCRYPTED",
				"THREAT POSTURE: PATROL",
				"UPLINK: STABLE"
			],
			"status_terminal": [
				"ACCESS LEVEL: RESTRICTED",
				"ACTIVE SESSIONS: 1",
				"STORAGE: ##% USED",
				"LAST LOGIN: ####-##-## ##:##"
			],
			"status_disruptor": [
				"CHARGE STATE: READY",
				"OUTPUT MODE: PULSE",
				"SYNC: STANDBY",
				"RANGE PROFILE: LOCAL"
			],
			"status_escalation": [
				"COUNTERMEASURE LINK: LIVE",
				"THREAT WEIGHTING: ESCALATING",
				"RESPONSE MESH: STAGED",
				"ALERT ROUTING: GLOBAL"
			]
		},
		SECTION_CORP_SPECIFIC: {}
	}

static func _build_session_line(active_sig: ActiveSignal) -> String:
	var signal_data := active_sig.data
	return "[SESSION: %s - %s]" % [signal_data.system_id, _get_device_label(signal_data)]

static func _build_status_block(active_sig: ActiveSignal, corp_id: String) -> Array[String]:
	var status_lines: Array[String] = []
	var used_lines: Dictionary = {}

	var primary_status := "STATUS: OFFLINE" if active_sig.is_disabled else "STATUS: ONLINE"
	status_lines.append(primary_status)
	used_lines[primary_status] = true

	var type_category := _get_type_status_category(active_sig.data.type)
	var type_line := _pick_unique_line(type_category, used_lines, corp_id)
	if not type_line.is_empty():
		status_lines.append(type_line)

	while status_lines.size() < STATUS_LINE_COUNT:
		var universal_line := _pick_unique_line("status_universal", used_lines, corp_id)
		if universal_line.is_empty():
			break
		status_lines.append(universal_line)

	return status_lines

static func _build_installed_line(active_sig: ActiveSignal) -> String:
	var modules: Array[String] = _collect_installed_modules(active_sig)
	if modules.is_empty():
		return "INSTALLED: none"
	return "INSTALLED: " + ", ".join(modules)

static func _build_puzzle_hint_block(active_sig: ActiveSignal) -> Array[String]:
	var lines: Array[String] = []
	if active_sig == null or active_sig.data == null or active_sig.data.puzzle == null:
		return lines

	var puzzle := active_sig.data.puzzle
	if not puzzle.is_locked():
		return lines

	var disclosure := _roll_puzzle_disclosure(puzzle.difficulty)
	lines.append(_build_puzzle_lock_line(puzzle, disclosure))

	if disclosure == PuzzleDisclosure.LOCK_ONLY:
		return lines

	lines.append(_build_puzzle_program_line(puzzle))

	if disclosure == PuzzleDisclosure.FULL:
		var hint_line := _build_puzzle_detail_line(puzzle)
		if not hint_line.is_empty():
			lines.append(hint_line)

	return lines

static func _build_ic_connection_block(active_sig: ActiveSignal) -> Array[String]:
	if active_sig == null or active_sig.data == null or active_sig.data.ic_modules == null:
		return []
	return active_sig.data.ic_modules.get_connection_flow_lines(active_sig)

static func _collect_installed_modules(active_sig: ActiveSignal) -> Array[String]:
	var modules: Array[String] = []
	if active_sig == null or active_sig.data == null:
		return modules

	var signal_data := active_sig.data
	match signal_data.type:
		SignalData.Type.CAMERA:
			modules.append_array(["record.sys", "vision.sys"])
		SignalData.Type.DOOR:
			modules.append_array(["access.sys", "bolt.sys"])
		SignalData.Type.DRONE:
			modules.append_array(["nav.sys", "telemetry.sys"])
		SignalData.Type.GUARD:
			modules.append_array(["bio_link.sys", "comms.sys"])
		SignalData.Type.TERMINAL:
			modules.append_array(["session.sys", "audit.sys"])
		SignalData.Type.DISRUPTOR:
			modules.append_array(["pulse.sys", "targeting.sys"])
		SignalData.Type.ESCALATION:
			modules.append_array(["threat_mesh.sys", "dispatch.sys"])
		_:
			modules.append("kernel.sys")

	if signal_data.puzzle != null:
		modules.append(_get_puzzle_module_name(signal_data.puzzle))
	if signal_data.ic_modules != null:
		modules.append("watchdog.sys")
	if signal_data.detection != null:
		modules.append("alarm.sys")
	if signal_data.response != null:
		modules.append("response.sys")
	if signal_data.mobility != null:
		modules.append("route.sys")

	return _dedupe_lines(modules)

static func _get_puzzle_module_name(puzzle: PuzzleComponent) -> String:
	if puzzle == null:
		return "auth.sys"
	match puzzle.puzzle_type:
		PuzzleComponent.Type.SNIFF:
			return "stream.sys"
		PuzzleComponent.Type.FUZZ:
			return "fuzzlock.sys"
		PuzzleComponent.Type.DECRYPT:
			return "cipher.sys"
		_:
			return "auth.sys"

static func _roll_puzzle_disclosure(difficulty: int) -> PuzzleDisclosure:
	var weights: Dictionary = PUZZLE_DISCLOSURE_WEIGHTS.get(difficulty, PUZZLE_DISCLOSURE_WEIGHTS[3])
	var roll := randf()
	var running_total := 0.0
	for disclosure in [
		PuzzleDisclosure.FULL,
		PuzzleDisclosure.PROGRAM_ONLY,
		PuzzleDisclosure.LOCK_ONLY
	]:
		running_total += float(weights.get(disclosure, 0.0))
		if roll <= running_total:
			return disclosure
	return PuzzleDisclosure.LOCK_ONLY

static func _build_puzzle_lock_line(puzzle: PuzzleComponent, disclosure: PuzzleDisclosure) -> String:
	match puzzle.puzzle_type:
		PuzzleComponent.Type.DECRYPT:
			match disclosure:
				PuzzleDisclosure.LOCK_ONLY:
					return "SECURITY GATE: Archive seal engaged. Handshake refused."
				_:
					return "SECURITY GATE: [color=orange]Encrypted channel[/color] active."
		PuzzleComponent.Type.SNIFF:
			match disclosure:
				PuzzleDisclosure.LOCK_ONLY:
					return "SECURITY GATE: Traffic mask engaged. Session reads as sealed."
				_:
					return "SECURITY GATE: [color=orange]Obfuscated datastream[/color] detected."
		PuzzleComponent.Type.FUZZ:
			match disclosure:
				PuzzleDisclosure.LOCK_ONLY:
					return "SECURITY GATE: Fault barrier engaged. Direct override rejected."
				_:
					return "SECURITY GATE: [color=orange]Instability-locked surface[/color] detected."
		_:
			return "SECURITY GATE: Access restrictions active."

static func _build_puzzle_program_line(puzzle: PuzzleComponent) -> String:
	match puzzle.puzzle_type:
		PuzzleComponent.Type.DECRYPT:
			return "Loader notes: [color=cyan]DECRYPT[/color]-class handshake accepted."
		PuzzleComponent.Type.SNIFF:
			return "Loader notes: [color=cyan]SNIFF[/color]-class listener accepted."
		PuzzleComponent.Type.FUZZ:
			return "Loader notes: [color=cyan]FUZZ[/color]-class injector accepted."
		_:
			return "Loader notes: specialized override required."

static func _build_puzzle_detail_line(puzzle: PuzzleComponent) -> String:
	match puzzle.puzzle_type:
		PuzzleComponent.Type.DECRYPT:
			return _build_decrypt_hint_line(puzzle)
		PuzzleComponent.Type.SNIFF:
			return _build_sniff_hint_line(puzzle)
		PuzzleComponent.Type.FUZZ:
			return _build_fuzz_hint_line(puzzle)
		_:
			return ""

static func _build_decrypt_hint_line(puzzle: PuzzleComponent) -> String:
	var decrypt_config := puzzle.get_decrypt_config()
	if decrypt_config == null:
		return "Cipher suite: REP-STD | Grade: LEGACY | Keyspace: PARTIAL"

	match decrypt_config.cipher:
		DecryptPuzzleConfig.Cipher.REPLACEMENT:
			return "Cipher suite: REP-STD+ | Offset: 0x%02X | Mode: MONO-ALPHA" % decrypt_config.mapping_offset
		_:
			return "Cipher suite: UNKNOWN | Grade: SEALED"

static func _build_sniff_hint_line(puzzle: PuzzleComponent) -> String:
	var sniff_config := puzzle.get_sniff_config()
	if sniff_config == null:
		return "Traffic profile: HEX-SWEEP | Signature density: LOW"

	var axis := "VERTICAL" if sniff_config.scroll_direction == SniffPuzzleConfig.ScrollDirection.VERTICAL else "HORIZONTAL"
	return "Traffic profile: HEX-SWEEP | Grid: %dx%d | Tokens: %d | Axis: %s" % [
		sniff_config.grid_cols,
		sniff_config.grid_rows,
		sniff_config.target_count,
		axis
	]

static func _build_fuzz_hint_line(puzzle: PuzzleComponent) -> String:
	var config := puzzle.get_fuzz_config()
	if config == null:
		return "Fault profile: UNKNOWN"
	return "Fault profile: ANGULAR | Probe budget: %d packets | Recovery: %.1f/s" % [config.max_ammo, config.regeneration_per_second]

static func _dedupe_lines(lines: Array[String]) -> Array[String]:
	var seen: Dictionary = {}
	var out: Array[String] = []
	for line in lines:
		if seen.has(line):
			continue
		seen[line] = true
		out.append(line)
	return out

static func _get_type_status_category(signal_type: int) -> String:
	match signal_type:
		SignalData.Type.CAMERA:
			return "status_camera"
		SignalData.Type.DOOR:
			return "status_door"
		SignalData.Type.DRONE:
			return "status_drone"
		SignalData.Type.GUARD:
			return "status_guard"
		SignalData.Type.TERMINAL:
			return "status_terminal"
		SignalData.Type.DISRUPTOR:
			return "status_disruptor"
		SignalData.Type.ESCALATION:
			return "status_escalation"
		_:
			return "status_universal"

static func _get_device_label(signal_data: SignalData) -> String:
	if signal_data == null:
		return "Unknown Device"
	if not signal_data.display_name.is_empty() and signal_data.display_name != signal_data.system_id:
		return signal_data.display_name
	if signal_data.type in signal_data.identity_dict:
		return signal_data.identity_dict[signal_data.type]
	return "Unknown Device"

static func _pick_unique_line(category: String, used_lines: Dictionary, corp_id: String = "") -> String:
	var lines := get_lines(category, corp_id)
	var candidates: Array[String] = []
	for line in lines:
		if not used_lines.has(line):
			candidates.append(line)

	if candidates.is_empty():
		return ""

	var choice = candidates.pick_random()
	used_lines[choice] = true
	return choice
