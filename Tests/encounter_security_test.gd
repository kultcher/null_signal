extends Node

# Randomized encounter security (EncounterSecurity): per-tier rates match the
# design table within sampling tolerance, host eligibility holds, rolls are
# reproducible, and the rolled modules reach the runtime signals.
# Run: godot --headless res://Tests/encounter_security_test.tscn

const ENCOUNTERS_PER_TIER := 400
const TOLERANCE := 0.05
# Expected share of hackable signals: any IC, heavy package, extra Tier III;
# share of wildcard templates that rolled their wildcard; puzzle [low, high, low share].
const EXPECTED := {
	1: {"any": 0.75, "heavy": 0.00, "tier3": 0.00, "wildcard": 0.30, "puzzle": [1, 2, 0.7]},
	2: {"any": 0.90, "heavy": 0.20, "tier3": 0.00, "wildcard": 0.45, "puzzle": [2, 3, 0.7]},
	3: {"any": 1.00, "heavy": 0.50, "tier3": 0.00, "wildcard": 0.60, "puzzle": [3, 4, 0.7]},
	4: {"any": 1.00, "heavy": 1.00, "tier3": 0.25, "wildcard": 0.75, "puzzle": [4, 5, 0.7]},
	5: {"any": 1.00, "heavy": 1.00, "tier3": 0.50, "wildcard": 0.90, "puzzle": [4, 5, 0.3]},
}

var failures := 0
var run := RunDefinition.new()

func check(label: String, condition: bool) -> void:
	if not condition:
		failures += 1
	print(("PASS " if condition else "FAIL ") + label)

func _ready() -> void:
	for tier in range(1, 6):
		_check_tier(tier)
	_check_determinism()
	_check_authored_unchanged()
	_check_runtime_modules()
	print("ENCOUNTER SECURITY TEST: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _check_tier(tier: int) -> void:
	var expected: Dictionary = EXPECTED[tier]
	var signals := 0
	var any := 0
	var heavy := 0
	var tier3 := 0
	var wild_templates := 0
	var wild_rolled := 0
	var doors := 0
	var door_puzzles := 0
	var low_puzzles := 0
	var puzzle_range_ok := true
	var eligibility_ok := true
	var counts_ok := true
	var rng := RandomNumberGenerator.new()
	for i in ENCOUNTERS_PER_TIER:
		var template_id: StringName = EncounterLibrary.IDS[i % EncounterLibrary.IDS.size()]
		rng.seed = 1000 * tier + i
		var inst := EncounterLibrary.make(template_id, tier).generate(run, 0.0, rng, "t%d_%d" % [tier, i], tier)
		if template_id in [&"camera_corridor", &"drone_patrol"]:
			wild_templates += 1
			wild_rolled += 1 if inst.wildcard_active else 0
		for spawn in inst.spawns:
			var data: SignalData = spawn["signal_data"]
			var kind := EncounterSecurity.host_kind(data)
			var record: Dictionary = inst.security.get(spawn["system_id"], {})
			if kind == &"none":
				eligibility_ok = eligibility_ok and record.is_empty()
				continue
			signals += 1
			var ic: Array = record.ic.map(func(entry): return String(entry).get_slice(":", 0))
			any += 1 if not ic.is_empty() else 0
			heavy += 1 if String(record.package).begins_with("heavy") else 0
			tier3 += 1 if ic.any(func(name): return name in EncounterSecurity.IC_TIERS[3]) else 0
			counts_ok = counts_ok and ic.size() <= 3 and ic.size() == _unique(ic).size()
			for name in ic:
				if name in EncounterSecurity.NEEDS_DISABLE and kind != &"device":
					eligibility_ok = false
			if kind == &"disruptor" and not String(record.puzzle).is_empty():
				eligibility_ok = false
			if kind == &"door":
				doors += 1
				if not String(record.puzzle).is_empty():
					door_puzzles += 1
					var level := int(String(record.puzzle).get_slice(":", 1))
					puzzle_range_ok = puzzle_range_ok and level in [expected.puzzle[0], expected.puzzle[1]]
					low_puzzles += 1 if level == expected.puzzle[0] else 0
	var tag := "tier %d:" % tier
	_near("%s signals with any IC" % tag, float(any) / signals, expected.any)
	_near("%s heavy packages (two Tier I or a Tier II)" % tag, float(heavy) / signals, expected.heavy)
	_near("%s extra Tier III" % tag, float(tier3) / signals, expected.tier3)
	_near("%s wildcard rate" % tag, float(wild_rolled) / wild_templates, expected.wildcard)
	check("%s every door has a puzzle" % tag, door_puzzles == doors and doors > 0)
	check("%s puzzle difficulty within %d-%d" % [tag, expected.puzzle[0], expected.puzzle[1]], puzzle_range_ok)
	_near("%s puzzle low-end share" % tag, float(low_puzzles) / door_puzzles, expected.puzzle[2], 0.08)
	check("%s Reboot/Heartbeat/Tripwire only on devices; guards and disruptor puzzles skipped" % tag, eligibility_ok)
	check("%s at most three distinct IC per signal" % tag, counts_ok)

func _near(label: String, actual: float, expected: float, tolerance := TOLERANCE) -> void:
	check("%s %.2f ~ %.2f" % [label, actual, expected], absf(actual - expected) <= tolerance)

func _unique(values: Array) -> Array:
	var result: Array = []
	for value in values:
		if not value in result:
			result.append(value)
	return result

func _check_determinism() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 77
	b.seed = 77
	var one := EncounterLibrary.make(&"drone_patrol", 4).generate(run, 0.0, a, "x", 4)
	var two := EncounterLibrary.make(&"drone_patrol", 4).generate(run, 0.0, b, "x", 4)
	check("same seed rolls the same security and wildcard", one.security == two.security and one.wildcard == two.wildcard)

func _check_authored_unchanged() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var inst := EncounterLibrary.make(&"watched_door", 1).generate(run, 0.0, rng, "a")
	check("tier 0 keeps authored security and records none", inst.security_tier == 0 and inst.security.is_empty() and inst.wildcard_active)
	var door: Dictionary = inst.spawns.filter(func(s): return inst.roles[s.system_id] == "door")[0]
	check("authored watched door keeps its sniff puzzle", door.has("puzzle") and door.puzzle.puzzle_type == PuzzleComponent.Type.SNIFF)

func _check_runtime_modules() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var inst := EncounterLibrary.make(&"camera_corridor", 5).generate(run, 0.0, rng, "r", 5)
	var ok := true
	for spawn in inst.spawns:
		var data := run.build_runtime_signal(spawn)
		var record: Dictionary = inst.security.get(spawn.system_id, {})
		var names: Array = data.ic_modules.modules.map(func(m): return CostTable.ic_key(m))
		var rolled: Array = record.get("ic", []).map(func(entry): return String(entry).get_slice(":", 0))
		ok = ok and names == rolled
	check("runtime signals carry exactly the rolled IC", ok)
	check("description lists the rolled security", inst.describe().contains("security T5"))
