# CostTable.gd
# Time cost of solving a signal, looked up from Resources/Analysis/cost_table.json.
# Entries are seconds split into:
#   blocking   - the player's attention is tied up (puzzle open, picking commands)
#   background - runs on its own while the player does other things (scan layers)
# Every entry carries source ("code", "guess", "telemetry") and samples so the
# table can be replaced piece by piece as playtest data comes in.
# See DesignNotes/ThreatAndCost.md.
class_name CostTable extends RefCounted

const DEFAULT_PATH := "res://Resources/Analysis/cost_table.json"

# Seconds of runner travel that are "free" before a hold is needed; mirrors the
# decision window from ReachAnalyzer.
enum Fit { FITS, TIGHT, HOLD, PREEMPTIVE, NO_THREAT }
const FIT_NAMES := {
	Fit.FITS: "fits",
	Fit.TIGHT: "tight",
	Fit.HOLD: "hold",
	Fit.PREEMPTIVE: "preemptive",
	Fit.NO_THREAT: "no threat",
}

var table: Dictionary = {}
var path: String = DEFAULT_PATH

static var _cached: CostTable = null

static func shared() -> CostTable:
	if _cached == null:
		_cached = CostTable.load_from(DEFAULT_PATH)
	return _cached

static func load_from(file_path: String) -> CostTable:
	var t := CostTable.new()
	t.path = file_path
	var text := FileAccess.get_file_as_string(file_path)
	if text.is_empty():
		push_warning("CostTable: could not read %s" % file_path)
		return t
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		t.table = parsed
	else:
		push_warning("CostTable: %s is not a JSON object" % file_path)
	return t

# Returns:
#   blocking, background, total  - seconds
#   items      - [{key, blocking, background, source, samples}]
#   guesses    - how many items are still source "guess"
#   unknown    - how many items fell back to the unknown entry
static func empty_estimate() -> Dictionary:
	return {"blocking": 0.0, "background": 0.0, "total": 0.0, "items": [], "guesses": 0, "unknown": 0}

func estimate(data: SignalData) -> Dictionary:
	var est := empty_estimate()
	if data == null:
		return est
	var base: Dictionary = table.get("base", {})

	# Scan: IDENTITY + ACCESS + one layer per IC module (or "IC: None").
	_add(est, "scan_identity", base.get("scan_identity", null))
	_add(est, "scan_access", base.get("scan_access", null))
	var ic_count := 0
	if data.ic_modules != null:
		for module in data.ic_modules.modules:
			if module != null:
				ic_count += 1
	for i in maxi(1, ic_count):
		_add(est, "scan_ic_layer", base.get("scan_ic_layer", null))

	if not _is_engageable(data):
		_finish(est)
		return est

	_add(est, "notice", base.get("notice", null))
	_add(est, "connect", base.get("connect", null))
	_add(est, "command", base.get("command", null))

	if data.puzzle != null and data.puzzle.puzzle_type != PuzzleComponent.Type.NONE:
		var ptype := puzzle_key(data.puzzle.puzzle_type)
		var diff := maxi(1, data.puzzle.difficulty)
		var by_diff: Dictionary = table.get("puzzles", {}).get(ptype, {})
		_add(est, "puzzle_%s_%d" % [ptype, diff], _pick(by_diff, diff))

	if data.ic_modules != null:
		var ic_table: Dictionary = table.get("ic", {})
		for module in data.ic_modules.modules:
			if module == null:
				continue
			var id := ic_key(module)
			var diff := maxi(1, int(module.get("base_difficulty")))
			_add(est, "ic_" + id, _pick(ic_table.get(id, null), diff))

	_finish(est)
	return est

# Compare an estimate against a ReachAnalyzer report. Window is the seconds of
# runner travel between "can touch it" and "it can touch the runner".
static func fit(estimate: Dictionary, report: Dictionary, hustle := false) -> Dictionary:
	var out := {"fit": Fit.NO_THREAT, "label": FIT_NAMES[Fit.NO_THREAT], "hold_sec": 0.0, "window": INF}
	if report.is_empty():
		return out
	var reach := String(report.get("reach", "n/a"))
	if reach == "never" or reach == "n/a" or reach == "open":
		return out
	var window: float = report.get("window_hustle" if hustle else "window_walk", INF)
	out["window"] = window
	var total: float = estimate.get("total", 0.0)
	var blocking: float = estimate.get("blocking", 0.0)
	var f := Fit.FITS
	if window < 0.0:
		# It threatens before the runner gets in range: solve it from further
		# back (if visible) or the runner has to wait.
		f = Fit.PREEMPTIVE
		out["hold_sec"] = total
	elif total <= window:
		f = Fit.FITS
	elif blocking <= window:
		# Fits only if background work overlaps the walk.
		f = Fit.TIGHT
	else:
		f = Fit.HOLD
		out["hold_sec"] = total - window
	out["fit"] = f
	out["label"] = FIT_NAMES[f]
	return out

static func puzzle_key(t: int) -> String:
	match t:
		PuzzleComponent.Type.SNIFF: return "sniff"
		PuzzleComponent.Type.DECRYPT: return "decrypt"
		PuzzleComponent.Type.FUZZ: return "fuzz"
	return "none"

static func ic_key(module: Resource) -> String:
	var id := ""
	if module.has_method("get_codex_id"):
		id = String(module.get_codex_id())
	if id.is_empty():
		id = String(module.get("codex_id"))
	if id.is_empty():
		var script: Script = module.get_script()
		id = script.resource_path.get_file().get_basename() if script else "unknown"
		id = id.trim_suffix("Module")
	return id.trim_prefix("codex_").to_lower()

static func _is_engageable(data: SignalData) -> bool:
	return data.hackable != null or data.puzzle != null \
		or (data.ic_modules != null and not data.ic_modules.modules.is_empty())

# Entries are either flat {blocking, background, ...} or keyed by difficulty
# ("1", "2", ...). Difficulty past the table end uses the last row.
func _pick(entry, difficulty: int):
	if not (entry is Dictionary) or entry.is_empty():
		return null
	if entry.has("blocking") or entry.has("background"):
		return entry
	var key := str(difficulty)
	if entry.has(key):
		return entry[key]
	var best := -1
	for k in entry.keys():
		var n := int(k)
		if n <= difficulty and n > best:
			best = n
	if best < 0:
		for k in entry.keys():
			if best < 0 or int(k) < best:
				best = int(k)
	return entry.get(str(best), null)

func _add(est: Dictionary, key: String, entry) -> void:
	var unknown := false
	if not (entry is Dictionary):
		entry = table.get("unknown", {"blocking": 0.0, "background": 0.0, "source": "guess"})
		unknown = true
	var item := {
		"key": key,
		"blocking": float(entry.get("blocking", 0.0)),
		"background": float(entry.get("background", 0.0)),
		"source": String(entry.get("source", "guess")),
		"samples": int(entry.get("samples", 0)),
	}
	est["items"].append(item)
	est["blocking"] += item["blocking"]
	est["background"] += item["background"]
	if item["source"] == "guess":
		est["guesses"] += 1
	if unknown:
		est["unknown"] += 1

func _finish(est: Dictionary) -> void:
	est["total"] = est["blocking"] + est["background"]
