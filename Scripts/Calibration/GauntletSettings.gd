class_name GauntletSettings extends Resource

# These modules can affect a single door without additional targets.
const DISRUPTIVE_IC := ["lag", "spammer", "degrade", "blackout", "glitch", "redact"]
const DOOR_IC := ["bouncer", "callback", "faraday", "haze", "trace", "shy", "siphon"] + DISRUPTIVE_IC
const PUZZLES := ["sniff", "decrypt", "fuzz"]
# These need their host disabled (OP can't do that to a door), so they run on
# a camera host on the route instead.
const CAMERA_IC := ["reboot", "heartbeat", "tripwire"]
const ENCOUNTERS := ["watched_door", "camera_corridor", "drone_patrol", "guard_patrol"]
const MAX_LEAD_CELLS := 7.0

@export var tester := "tester"
@export var skill_tag := "unspecified"
@export var shuffle_seed: int = 1
@export var isolated_elements := true
@export var include_baseline := true
@export_range(0, 16, 1) var ic_count := 1
@export_range(1, 20, 1) var ic_min := 1
@export_range(1, 20, 1) var ic_max := 1
@export var ic_pool: PackedStringArray = PackedStringArray(DOOR_IC)
@export var puzzle_enabled := true
@export_range(1, 20, 1) var puzzle_min := 1
@export_range(1, 20, 1) var puzzle_max := 1
@export var puzzle_pool: PackedStringArray = PackedStringArray(PUZZLES)
@export_range(0.1, 30, 0.1) var breach_delay_sec := 3.0
@export_range(0, 10, 0.1) var next_delay_sec := 1.0
@export_range(0.01, 2, 0.01) var runner_speed := 0.15
@export var reset_heat_each_trial := true
@export var fuzz_config: FuzzPuzzleConfig

# --- encounters, windows, session hygiene ---
# "elements": one signal per trial (door or camera host). "encounters": whole
# encounter templates (EncounterLibrary), each recorded as a group of trials.
@export_enum("elements", "encounters") var trial_source := "elements"
# Element host. "camera" puts a stationary camera on the route; it accepts the
# door IC plus CAMERA_IC. Success = runner passes it unseen.
@export_enum("door", "camera") var host := "door"
@export var encounter_pool: PackedStringArray = PackedStringArray(ENCOUNTERS)
@export_range(1, 5, 1) var encounter_difficulty := 1
# Cadence: >0 spawns the next encounter this many seconds after the previous
# one even if it's still active (up to max_concurrent). 0 = one at a time.
@export_range(0, 120, 0.5) var cadence_sec := 0.0
@export_range(1, 4, 1) var max_concurrent := 2
# Window sweep: distances (cells ahead of the runner) to spawn at. Each case
# is run at every distance. Empty = spawn at the screen edge.
@export var lead_cells: PackedFloat32Array = PackedFloat32Array()
# The first N trials/encounters of a session are flagged warm-up.
@export_range(0, 20, 1) var warmup_trials := 3
# Compare an authored encounter to the same template with added disruption on
# one designated host. Existing template puzzles and IC are retained.
@export var encounter_disruptions := false
# Encounter security: "authored" keeps each template's own setup;
# "randomized" rolls IC, puzzles and the wildcard from EncounterSecurity at the
# Enc. difficulty tier (1-5). Added disruptive IC still layer on top.
@export_enum("authored", "randomized") var encounter_security := "authored"

func available_ic() -> Array:
	return DOOR_IC + CAMERA_IC if host == "camera" else DOOR_IC.duplicate()

func encounter_ic_pool() -> PackedStringArray:
	var result := PackedStringArray()
	for key in ic_pool:
		if key in DISRUPTIVE_IC:
			result.append(key)
	return result

func normalized_copy() -> GauntletSettings:
	var copy := duplicate(true) as GauntletSettings
	copy.ic_pool = PackedStringArray()
	for key in ic_pool:
		if key in available_ic() and not key in copy.ic_pool:
			copy.ic_pool.append(key)
	copy.puzzle_pool = PackedStringArray()
	for key in puzzle_pool:
		if key in PUZZLES and not key in copy.puzzle_pool:
			copy.puzzle_pool.append(key)
	copy.ic_count = clampi(ic_count, 0, copy.ic_pool.size())
	copy.ic_min = clampi(ic_min, 1, 20)
	copy.ic_max = clampi(ic_max, copy.ic_min, 20)
	copy.puzzle_min = clampi(puzzle_min, 1, 20)
	copy.puzzle_max = clampi(puzzle_max, copy.puzzle_min, 20)
	copy.puzzle_enabled = puzzle_enabled and not copy.puzzle_pool.is_empty()
	copy.breach_delay_sec = maxf(0.1, breach_delay_sec)
	copy.next_delay_sec = maxf(0.0, next_delay_sec)
	copy.runner_speed = maxf(0.01, runner_speed)
	copy.trial_source = trial_source if trial_source in ["elements", "encounters"] else "elements"
	copy.host = host if host in ["door", "camera"] else "door"
	copy.encounter_pool = PackedStringArray()
	for key in encounter_pool:
		if key in ENCOUNTERS and not key in copy.encounter_pool:
			copy.encounter_pool.append(key)
	if copy.encounter_pool.is_empty():
		copy.encounter_pool = PackedStringArray(ENCOUNTERS)
	copy.encounter_difficulty = clampi(encounter_difficulty, 1, 5)
	copy.encounter_security = encounter_security if encounter_security in ["authored", "randomized"] else "authored"
	copy.cadence_sec = maxf(0.0, cadence_sec)
	copy.max_concurrent = clampi(max_concurrent, 1, 4)
	copy.lead_cells = PackedFloat32Array()
	for lead in lead_cells:
		var value := clampf(lead, 0.5, MAX_LEAD_CELLS)
		if lead > 0.0 and not value in copy.lead_cells:
			copy.lead_cells.append(value)
	copy.lead_cells.sort()
	copy.warmup_trials = maxi(0, warmup_trials)
	if copy.trial_source == "encounters":
		copy.ic_count = mini(copy.ic_count, copy.encounter_ic_pool().size())
	return copy

# "3, 5, 8" -> [3, 5, 8]; blank or invalid entries are dropped.
static func parse_leads(text: String) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for part in text.split(",", false):
		var token := part.strip_edges()
		if token.is_valid_float() and float(token) > 0.0:
			result.append(float(token))
	return result

static func format_leads(values: PackedFloat32Array) -> String:
	var parts: Array[String] = []
	for value in values:
		parts.append(str(value))
	return ", ".join(parts)
