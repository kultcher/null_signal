# EncounterSecurity.gd
# Rolls IC and puzzles onto an encounter's signals from a difficulty tier
# (1-5). Baseline numbers from design (2026-10-12); expected to be retuned from
# gauntlet data. Rolls use the encounter's own RNG, so a seed reproduces them.
#
# Per hackable signal, an IC "package" is rolled:
#   none   no IC
#   light  one Tier I
#   heavy  two Tier I, or one Tier II (50/50)
# plus, at tiers 4-5, a chance of an extra Tier III on top. So a signal can
# carry up to three IC: stacking is intended (and shows which IC clash).
#
# Puzzles: doors (and terminals) always get one; cameras/drones sometimes
# ("the occasional locked camera"); disruptors never. Guards aren't hackable
# and are left alone.
class_name EncounterSecurity extends RefCounted

# IC tiers. Tier I/II/III follow DesignNotes/ic_master.md where it assigns
# them; the PROVISIONAL ones aren't tiered there yet.
const IC_TIERS := {
	1: ["reboot", "faraday", "bouncer", "haze", "callback", "lag", "spammer", "shy", "redact"],
	2: ["trace", "degrade", "siphon", "heartbeat", "tripwire", "tether", "glitch"],
	3: ["blackout", "necromancer"],
}
const PROVISIONAL := ["shy", "redact", "siphon", "heartbeat", "tripwire", "tether", "glitch"]
# Only meaningful on something the player disables (cameras, drones).
const NEEDS_DISABLE := ["reboot", "heartbeat", "tripwire"]
const PUZZLES := ["sniff", "decrypt", "fuzz"]

# none / heavy: package odds (light is the remainder). base_heavy: every
# signal gets at least the heavy package. tier3: chance of an extra Tier III.
# puzzle: [low, high] difficulty, low_weight = chance of the low value.
# device_puzzle: chance a camera/drone is puzzle-locked.
# ic_difficulty: module difficulty for every rolled IC (data will refine).
const TIERS := {
	1: {"none": 0.25, "heavy": 0.0, "base_heavy": false, "tier3": 0.0, "puzzle": [1, 2], "low_weight": 0.7, "wildcard": 0.30, "device_puzzle": 0.0, "ic_difficulty": 1},
	2: {"none": 0.10, "heavy": 0.20, "base_heavy": false, "tier3": 0.0, "puzzle": [2, 3], "low_weight": 0.7, "wildcard": 0.45, "device_puzzle": 0.10, "ic_difficulty": 1},
	3: {"none": 0.0, "heavy": 0.50, "base_heavy": false, "tier3": 0.0, "puzzle": [3, 4], "low_weight": 0.7, "wildcard": 0.60, "device_puzzle": 0.15, "ic_difficulty": 2},
	4: {"none": 0.0, "heavy": 1.0, "base_heavy": true, "tier3": 0.25, "puzzle": [4, 5], "low_weight": 0.7, "wildcard": 0.75, "device_puzzle": 0.20, "ic_difficulty": 2},
	5: {"none": 0.0, "heavy": 1.0, "base_heavy": true, "tier3": 0.50, "puzzle": [4, 5], "low_weight": 0.3, "wildcard": 0.90, "device_puzzle": 0.25, "ic_difficulty": 3},
}
const MIN_TIER := 1
const MAX_TIER := 5

static func tier_settings(tier: int) -> Dictionary:
	return TIERS[clampi(tier, MIN_TIER, MAX_TIER)]

static func wildcard_chance(tier: int) -> float:
	return float(tier_settings(tier).wildcard)

# Which security a signal can carry: &"door", &"terminal", &"device"
# (cameras, drones), &"disruptor", or &"none" (guards, anything unhackable).
static func host_kind(data: SignalData) -> StringName:
	if data == null or data.hackable == null:
		return &"none"
	match data.type:
		SignalData.Type.DOOR: return &"door"
		SignalData.Type.TERMINAL, SignalData.Type.INFO: return &"terminal"
		SignalData.Type.CAMERA, SignalData.Type.DRONE: return &"device"
		SignalData.Type.DISRUPTOR: return &"disruptor"
	return &"none"

static func eligible_ic(kind: StringName, tier_of_ic: int) -> Array:
	var result: Array = []
	for ic in IC_TIERS[tier_of_ic]:
		if ic in NEEDS_DISABLE and kind != &"device":
			continue
		result.append(ic)
	return result

# Replaces the security on every hackable spawn of `inst` (authored puzzles
# and IC are overwritten) and records what was rolled in inst.security:
#   system_id -> {"kind", "package", "puzzle": "type:difficulty" or "", "ic": ["name:difficulty", ...]}
static func apply(run: RunDefinition, inst: EncounterInstance, rng: RandomNumberGenerator, tier: int) -> void:
	var t := tier_settings(tier)
	inst.security_tier = clampi(tier, MIN_TIER, MAX_TIER)
	inst.security = {}
	for spawn in inst.spawns:
		var data: SignalData = spawn["signal_data"]
		var kind := host_kind(data)
		var system_id: String = spawn.get("system_id", "")
		if kind == &"none":
			continue
		var record := {"kind": String(kind), "package": "none", "puzzle": "", "ic": []}
		# IC package.
		var picks: Array = []
		var package := _roll_package(rng, t)
		match package:
			"light":
				picks += _pick(rng, eligible_ic(kind, 1), 1, picks)
			"heavy":
				if rng.randf() < 0.5:
					picks += _pick(rng, eligible_ic(kind, 1), 2, picks)
				else:
					picks += _pick(rng, eligible_ic(kind, 2), 1, picks)
		if rng.randf() < float(t.tier3):
			picks += _pick(rng, eligible_ic(kind, 3), 1, picks)
			package += "+tier3"
		record.package = package
		var ic := ICComponent.new()
		var difficulty := int(t.ic_difficulty)
		for name in picks:
			var module = run.build_ic(StringName(name), difficulty)
			if module != null:
				ic.add_module(module)
				record.ic.append("%s:%d" % [name, difficulty])
		spawn["ic_modules"] = ic
		# Puzzle.
		var wants_puzzle := kind == &"door" or kind == &"terminal" or (kind == &"device" and rng.randf() < float(t.device_puzzle))
		if wants_puzzle:
			var puzzle_type: String = PUZZLES[rng.randi_range(0, PUZZLES.size() - 1)]
			var level: int = t.puzzle[0] if rng.randf() < float(t.low_weight) else t.puzzle[1]
			var puzzle := run.build_puzzle(StringName(puzzle_type), level)
			if puzzle != null:
				spawn["puzzle"] = puzzle
				record.puzzle = "%s:%d" % [puzzle_type, level]
		elif spawn.has("puzzle"):
			spawn.erase("puzzle")
		inst.security[system_id] = record

static func _roll_package(rng: RandomNumberGenerator, t: Dictionary) -> String:
	if bool(t.base_heavy):
		return "heavy"
	var roll := rng.randf()
	if roll < float(t.none):
		return "none"
	if roll < float(t.none) + float(t.heavy):
		return "heavy"
	return "light"

# `count` distinct IC from `pool`, skipping ones already chosen.
static func _pick(rng: RandomNumberGenerator, pool: Array, count: int, taken: Array) -> Array:
	var available := pool.filter(func(ic): return not ic in taken)
	var chosen: Array = []
	for i in mini(count, available.size()):
		var index := rng.randi_range(0, available.size() - 1)
		chosen.append(available[index])
		available.remove_at(index)
	return chosen

# One-line summary per signal, e.g. "door: decrypt:3 + bouncer:2, trace:2".
static func describe(inst: EncounterInstance) -> String:
	var parts: Array[String] = []
	for system_id in inst.security:
		var record: Dictionary = inst.security[system_id]
		var bits: Array[String] = []
		if not String(record.puzzle).is_empty():
			bits.append(record.puzzle)
		if not record.ic.is_empty():
			bits.append(", ".join(record.ic))
		parts.append("%s: %s" % [inst.roles.get(system_id, system_id), " + ".join(bits) if not bits.is_empty() else "open"])
	return "; ".join(parts)
