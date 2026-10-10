extends Node

# Reach analyzer + cost table checks. Run as a scene (autoloads are needed by
# RunDefinition.build_runtime_signal):
#   godot --headless res://Tests/threat_analysis_test.tscn

const TUTORIAL := "res://Resources/RunData/AuthoredRuns/TutorialRun.gd"
const NIGHT_AUDIT := "res://Resources/RunData/AuthoredRuns/NightAuditRun.gd"

var failures := 0

func _ready() -> void:
	var tutorial := _analyze(TUTORIAL)
	var tut: Dictionary = tutorial["reports"]
	check("tutorial analyzed every signal", tut.size() == tutorial["entries"].size() and tut.size() > 0)
	check("cam_04 never reaches the route (matches play)", _reach(tut, "cam_04") == "never")
	check("cam_01 certain", _reach(tut, "cam_01") == "certain")
	if tut.has("cam_01") and not tut["cam_01"]["intervals"].is_empty():
		var first: Dictionary = tut["cam_01"]["intervals"][0]
		check("cam_01 covers cells ~3.4-4.6 (physics sim: 3.40-4.60) got %.2f-%.2f" % [first["from_cell"], first["to_cell"]], absf(first["from_cell"] - 3.4) < 0.15 and absf(first["to_cell"] - 4.6) < 0.15)
	check("door_01 is a blocker", tut.has("door_01") and tut["door_01"]["kind"] == "blocker")
	check("hit chances are probabilities", _all_hits_valid(tut))

	var audit := _analyze(NIGHT_AUDIT)
	var na: Dictionary = audit["reports"]
	for id in ["plate_cam", "guard_14f_a", "cam_14f_01", "cam_14f_02", "cam_antechamber", "guard_dock", "yard_cam"]:
		check("night audit %s never reaches the route" % id, _reach(na, id) == "never")
	check("night audit cam_records certain", _reach(na, "cam_records") == "certain")
	check("night audit cam_records has a positive decision window", na.has("cam_records") and na["cam_records"]["window_walk"] > 0.0)
	check("analysis is fast enough for reload (%d ms)" % audit["msec"], audit["msec"] < 3000)

	# Cost table
	var costs := CostTable.load_from(CostTable.DEFAULT_PATH)
	check("cost table loads", not costs.table.is_empty() and int(costs.table.get("version", 0)) == 1)
	var any_puzzle := false
	for entry in audit["entries"]:
		var data: SignalData = entry["data"]
		var est := costs.estimate(data)
		check("%s estimate totals add up" % data.system_id, is_equal_approx(est["total"], est["blocking"] + est["background"]))
		check("%s has no unknown cost entries" % data.system_id, est["unknown"] == 0)
		if data.puzzle != null and data.puzzle.puzzle_type != PuzzleComponent.Type.NONE:
			any_puzzle = true
			var key := "puzzle_%s_" % CostTable.puzzle_key(data.puzzle.puzzle_type)
			var found := false
			for item in est["items"]:
				found = found or String(item["key"]).begins_with(key)
			check("%s estimate includes its puzzle" % data.system_id, found)
	check("night audit has puzzles to cost", any_puzzle)

	var fake_report := {"reach": "certain", "window_walk": 10.0, "window_hustle": 3.0}
	var fake_est := {"blocking": 4.0, "background": 2.0, "total": 6.0}
	check("fit: fits at walk", CostTable.fit(fake_est, fake_report)["fit"] == CostTable.Fit.FITS)
	check("fit: hold at hustle", CostTable.fit(fake_est, fake_report, true)["fit"] == CostTable.Fit.HOLD and is_equal_approx(CostTable.fit(fake_est, fake_report, true)["hold_sec"], 3.0))
	fake_report["window_hustle"] = 5.0
	check("fit: tight when only blocking fits", CostTable.fit(fake_est, fake_report, true)["fit"] == CostTable.Fit.TIGHT)
	check("fit: never is no threat", CostTable.fit(fake_est, {"reach": "never"})["fit"] == CostTable.Fit.NO_THREAT)
	check("ic keys strip codex prefix", CostTable.ic_key(BouncerModule.new()) == "bouncer")

	print("THREAT TEST: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures > 0 else 0)

func _analyze(path: String) -> Dictionary:
	var run: RunDefinition = load(path).new()
	var layout := run.build_facility_layout()
	layout.set_lane_to_cell_scale(ReachAnalyzer.LANE_PX / ReachAnalyzer.CELL_PX)
	var entries: Array = []
	for spawn in run.get_spawns():
		var data := run.build_runtime_signal(spawn)
		if data.puzzle != null:
			data.puzzle.ensure_initial_lock_state()
		entries.append({"data": data, "cell": float(spawn["cell_index"])})
	var started := Time.get_ticks_msec()
	var reports := ReachAnalyzer.analyze(layout, entries)
	return {"reports": reports, "entries": entries, "msec": Time.get_ticks_msec() - started}

func _reach(reports: Dictionary, id: String) -> String:
	return String(reports[id]["reach"]) if reports.has(id) else "missing"

func _all_hits_valid(reports: Dictionary) -> bool:
	for report in reports.values():
		for key in ["hit_walk", "hit_hustle"]:
			var v: float = report[key]
			if v < 0.0 or v > 1.0:
				return false
	return true

func check(name: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + name)
