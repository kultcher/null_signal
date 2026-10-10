# ReachAnalyzer.gd
# Static "potential threat" analysis for authored runs: can a signal ever
# threaten the runner's route, where, how reliably, and how much warning does
# the player get? No gameplay nodes are created; the analysis replays each
# signal's authored behavior (vision sweep, patrol movement) on its own clock
# using the same vision polygons and runner detection radius as gameplay.
#
# Per signal it reports:
#   reach      "certain"  some route point is watched at every moment of the
#                         signal's cycle: the runner cannot pass unseen.
#              "possible" the route is watched only part of the time: whether
#                         the runner is seen depends on timing/speed.
#              "never"    its vision never touches the route.
#              "open"     unlocked door / nothing that can stop the runner.
#   intervals  route stretches (progress, in cells of path length) it covers,
#              with the max fraction of its cycle any point there is watched.
#   hit_walk / hit_hustle
#              chance of being seen walking through at base speed / hustling,
#              over evenly spaced phases of the signal's cycle.
#   interact_progress, threat_progress
#              first route point where the player can see and touch it, and
#              first route point it can threaten.
#   window_walk / window_hustle
#              seconds between the two at base speed / hustle: the decision
#              window. Negative means it threatens before it can be touched.
#
# Doors are "blockers": a locked door stops the runner where the route meets
# it (certain), rather than raising heat.
#
# Known simplifications: alerts/investigation, walls (vision isn't blocked by
# walls in gameplay either), runner holds, and escalation spawns are ignored.
# Phase-based hit chances assume a random relationship between the signal's
# clock and the runner's arrival; see DesignNotes/ThreatAndCost.md.

class_name ReachAnalyzer extends RefCounted

const CELL_PX := 240.0
const LANE_PX := 90.0
# Runner detection radius in map px: RunnerShape's 60px circle under the
# RunnerTeam node's 0.4 scale (run_main.tscn). Override with "runner_radius_px".
const RUNNER_RADIUS_PX := 24.0
const ROUTE_STEP := 0.05            # cells of path length between route samples
const POSE_DT := 0.1                # seconds between behavior samples
const MAX_CYCLE_SEC := 180.0
const PHASES := 24
const CERTAIN_RATIO := 0.999

const DEFAULT_PARAMS := {
	"base_speed": 0.15,             # TimelineManager.BASE_CELLS_PER_SECOND
	"hustle_mult": 3.0,             # TimelineManager.fast_speed_modifier
	"interaction_range": 8.0,       # TimelineManager.signal_interaction_range_cells
	"visible_cells": 8.0,           # TimelineManager.VISIBLE_CELLS
	"runner_offset_cells": 1.0,     # TimelineManager.runner_screen_offset_cells
	"spawn_margin_px": 200.0,       # SignalManager on-screen margin
	"runner_radius_px": RUNNER_RADIUS_PX,
}

# entries: [{"data": SignalData (runtime-resolved), "cell": float}], as built
# by the level viewer from RunDefinition.build_runtime_signal().
# Returns system_id -> report Dictionary.
static func analyze(layout: FacilityLayout, entries: Array, params: Dictionary = {}) -> Dictionary:
	var p := DEFAULT_PARAMS.duplicate()
	p.merge(params, true)
	var reports := {}
	for entry in entries:
		var data: SignalData = entry["data"]
		if data == null:
			continue
		reports[data.system_id] = analyze_signal(layout, data, float(entry["cell"]), p)
	return reports

static func analyze_signal(layout: FacilityLayout, data: SignalData, cell: float, params: Dictionary) -> Dictionary:
	var section := layout.get_section_for_cell(cell)
	var report := {
		"id": data.system_id,
		"section": section.id,
		"kind": _kind(data),
		"reach": "never",
		"intervals": [],
		"max_ratio": 0.0,
		"hit_walk": 0.0,
		"hit_hustle": 0.0,
		"interact_progress": _interact_progress(layout, section, cell, params),
		"threat_progress": -1.0,
		"window_walk": INF,
		"window_hustle": INF,
		"consequence": _consequence(data),
		"cycle_sec": 0.0,
		"mobile": _is_mobile(data),
	}
	if data.detection == null or data.type == SignalData.Type.TERMINAL or data.type == SignalData.Type.DISRUPTOR:
		report["reach"] = "n/a"
		return report
	if data.type == SignalData.Type.DOOR and not data.door_locked:
		report["reach"] = "open"
		return report

	var poses := _build_poses(data, cell)
	if poses.is_empty():
		return report
	report["cycle_sec"] = poses.size() * POSE_DT
	var shapes := _pose_shapes(data.detection, poses, float(params["runner_radius_px"]))

	# Route samples within reach of the envelope, in this signal's section.
	var envelope: Rect2 = shapes["envelope"]
	var samples: Array = []
	var progress := section.progress_start
	while progress <= section.get_progress_end():
		var point := layout.sample_position(progress)
		var world := Vector2(point.x * CELL_PX, point.y * LANE_PX)
		if envelope.has_point(world):
			samples.append({"progress": progress, "world": world})
		progress += ROUTE_STEP
	if samples.is_empty():
		return report

	# Fraction of the cycle each sample is watched.
	var intervals: Array = []
	var current := {}
	var max_ratio := 0.0
	for sample in samples:
		var hits := 0
		for i in poses.size():
			if _covers(shapes, i, sample["world"]):
				hits += 1
		var ratio := float(hits) / float(poses.size())
		if ratio > 0.0:
			max_ratio = maxf(max_ratio, ratio)
			if current.is_empty() or sample["progress"] - current["to"] > ROUTE_STEP * 1.5:
				current = {"from": sample["progress"], "to": sample["progress"], "max_ratio": ratio}
				intervals.append(current)
			else:
				current["to"] = sample["progress"]
				current["max_ratio"] = maxf(current["max_ratio"], ratio)
	if intervals.is_empty():
		return report

	for interval in intervals:
		interval["from_cell"] = layout.sample_position(interval["from"]).x
		interval["to_cell"] = layout.sample_position(interval["to"]).x
	report["intervals"] = intervals
	report["max_ratio"] = max_ratio
	report["reach"] = "certain" if max_ratio >= CERTAIN_RATIO else "possible"
	report["threat_progress"] = intervals[0]["from"]

	var base_speed: float = params["base_speed"]
	var hustle_speed: float = base_speed * float(params["hustle_mult"])
	report["hit_walk"] = _hit_chance(layout, shapes, poses.size(), intervals, base_speed)
	report["hit_hustle"] = _hit_chance(layout, shapes, poses.size(), intervals, hustle_speed)
	var lead: float = report["threat_progress"] - report["interact_progress"]
	report["window_walk"] = lead / base_speed
	report["window_hustle"] = lead / hustle_speed
	return report

# --- classification / text ---

static func _kind(data: SignalData) -> String:
	if data.type == SignalData.Type.DOOR:
		return "blocker"
	if data.detection != null and data.type != SignalData.Type.TERMINAL and data.type != SignalData.Type.DISRUPTOR:
		return "watcher"
	return "none"

static func _is_mobile(data: SignalData) -> bool:
	return data.mobility != null and data.mobility.enabled and not data.mobility.movement_disabled \
		and data.mobility.patrol_points.size() > 1

static func _consequence(data: SignalData) -> String:
	if data.type == SignalData.Type.DOOR:
		return "Stops the runner until opened"
	if data.response == null or data.response.effects.is_empty():
		return "None"
	var parts: Array[String] = []
	for effect in data.response.effects:
		if effect == null:
			continue
		var label := ""
		match int(effect.effect_type):
			ResponseEffect.EffectType.HEAT:
				label = "Heat %+d" % int(effect.amount)
			ResponseEffect.EffectType.DAMAGE:
				label = "Damage %d" % int(effect.amount)
			ResponseEffect.EffectType.STOP:
				label = "Stops runner"
		match int(effect.cadence):
			ResponseEffect.Cadence.CONTINUOUS:
				label += "/s while seen"
			ResponseEffect.Cadence.DELAYED:
				label += " after %.1fs" % effect.delay
		if effect.sends_alert:
			label += ", alerts guards"
		parts.append(label)
	return ", ".join(parts)

# --- interaction window ---

# First route progress (in the signal's section) where the signal is both on
# screen and within interaction range of the runner.
static func _interact_progress(layout: FacilityLayout, section: FacilitySection, cell: float, params: Dictionary) -> float:
	var visible_cells: float = params["visible_cells"]
	var offset: float = params["runner_offset_cells"]
	var margin_cells: float = float(params["spawn_margin_px"]) / CELL_PX
	var reach_cells: float = params["interaction_range"]
	var view_max := maxf(section.start_cell, section.end_cell - (visible_cells - offset))
	var progress := section.progress_start
	while progress <= section.get_progress_end():
		var runner_x := layout.sample_position(progress).x
		var view_cell := clampf(runner_x, section.start_cell, view_max)
		var screen_cells := cell - view_cell + offset
		if screen_cells < visible_cells + margin_cells and absf(cell - runner_x) <= reach_cells:
			return progress
		progress += ROUTE_STEP
	return section.progress_start

# --- behavior replay ---

# Time-sampled (world position, facing) over one behavior cycle.
static func _build_poses(data: SignalData, cell: float) -> Array:
	var det := data.detection
	var sweep: Array = []
	if det != null:
		sweep = det.patrol_points
	var mobile := _is_mobile(data)
	var start_facing: float = data.facing_deg
	if not sweep.is_empty():
		start_facing = sweep[0].facing_deg
	if not mobile and sweep.size() <= 1:
		return [{"pos": Vector2(cell * CELL_PX, data.lane * LANE_PX), "facing": start_facing}]

	# Detection sweep state (mirrors DetectionComponent.update_runtime).
	var facing: float = start_facing
	var sweep_index := 0
	var sweep_dir := 1
	var sweep_dwell := 0.0

	# Movement state (mirrors MobilityController patrol).
	var pos := Vector2(cell, float(data.lane))
	var points: Array = data.mobility.patrol_points if mobile else []
	var move_index := 0
	var move_dir := 1
	var move_dwell := 0.0
	var speed_px := (data.mobility.move_speed_cells_per_sec * CELL_PX) if mobile else 0.0
	var loop: bool = mobile and data.mobility.patrol_mode == MobilityComponent.PatrolMode.LOOP

	# One full cycle: each behavior goes round once (loop) or there and back
	# (ping-pong). Counted in arrivals; the first arrival (at the starting
	# point, usually immediate) starts the cycle, so stop on arrival N+1.
	# Movement and sweep periods can differ; we stop when both have finished
	# at least one cycle, which is close enough for coverage fractions.
	var move_arrivals_needed := 0
	if mobile:
		move_arrivals_needed = points.size() if loop else maxi(1, 2 * points.size() - 2)
	var sweep_arrivals_needed := 0 if sweep.size() <= 1 else maxi(1, 2 * sweep.size() - 2)
	var move_arrivals := 0
	var sweep_arrivals := 0
	var move_done := not mobile
	var sweep_done := sweep.size() <= 1

	var poses: Array = []
	var t := 0.0
	while t < MAX_CYCLE_SEC:
		var dt := POSE_DT
		# Move.
		if mobile:
			if move_dwell > 0.0:
				move_dwell -= dt
			else:
				var target: MobilityPatrolPoint = points[move_index]
				var step_px := speed_px * dt
				var lane_delta := float(target.lane) - pos.y
				var moved_dir := Vector2.ZERO
				if absf(lane_delta) > 0.001:
					var lane_step := step_px / LANE_PX
					pos.y = float(target.lane) if absf(lane_delta) <= lane_step else pos.y + signf(lane_delta) * lane_step
					moved_dir = Vector2(0.0, signf(lane_delta))
				else:
					var cell_delta := target.cell_x - pos.x
					if absf(cell_delta) > 0.001:
						var cell_step := step_px / CELL_PX
						pos.x = target.cell_x if absf(cell_delta) <= cell_step else pos.x + signf(cell_delta) * cell_step
						moved_dir = Vector2(signf(cell_delta), 0.0)
					else:
						move_dwell = maxf(0.0, target.dwell_sec)
						move_arrivals += 1
						if move_arrivals > move_arrivals_needed:
							move_done = true
						if loop:
							move_index = (move_index + 1) % points.size()
						else:
							var candidate := move_index + move_dir
							if candidate < 0 or candidate > points.size() - 1:
								move_dir *= -1
								candidate = move_index + move_dir
							move_index = clampi(candidate, 0, points.size() - 1)
				if sweep.is_empty() and det.follow_movement_facing and moved_dir != Vector2.ZERO:
					facing = rad_to_deg(atan2(moved_dir.y * LANE_PX, moved_dir.x * CELL_PX))
		# Sweep.
		if sweep.size() > 1:
			if sweep_dwell > 0.0:
				sweep_dwell -= dt
			else:
				var target_facing: float = sweep[sweep_index].facing_deg
				var current := wrapf(facing, -180.0, 180.0)
				var delta := wrapf(wrapf(target_facing, -180.0, 180.0) - current, -180.0, 180.0)
				var turn_step := det.turn_speed_deg_per_sec * dt
				if absf(delta) <= maxf(0.5, turn_step):
					facing = target_facing
					sweep_dwell = maxf(0.0, sweep[sweep_index].dwell_sec)
					sweep_arrivals += 1
					if sweep_arrivals > sweep_arrivals_needed:
						sweep_done = true
					var candidate := sweep_index + sweep_dir
					if candidate < 0 or candidate > sweep.size() - 1:
						sweep_dir *= -1
						candidate = sweep_index + sweep_dir
					sweep_index = clampi(candidate, 0, sweep.size() - 1)
				else:
					facing = wrapf(current + signf(delta) * turn_step, -180.0, 180.0)
		if move_done and sweep_done:
			break
		# Record after the first arrivals so the cycle starts in a settled state.
		if (move_arrivals > 0 or not mobile) and (sweep_arrivals > 0 or sweep.size() <= 1):
			poses.append({"pos": Vector2(pos.x * CELL_PX, pos.y * LANE_PX), "facing": facing})
		t += dt
	if poses.is_empty():
		poses.append({"pos": Vector2(pos.x * CELL_PX, pos.y * LANE_PX), "facing": facing})
	return poses

# Vision polygons per pose (world px), with bounding boxes and an envelope.
static func _pose_shapes(det: DetectionComponent, poses: Array, runner_radius: float) -> Dictionary:
	var local := det.get_visual_polygon(CELL_PX)
	var circle := det.shape_type == DetectionComponent.ShapeType.CIRCLE
	var radius := maxf(1.0, det.vision_length_cells * CELL_PX)
	var polygons: Array = []
	var boxes: Array = []
	var envelope := Rect2()
	for i in poses.size():
		var pose: Dictionary = poses[i]
		var poly := PackedVector2Array()
		var rad := deg_to_rad(float(pose["facing"]))
		for point in local:
			poly.append(pose["pos"] + point.rotated(rad))
		var box := Rect2(poly[0], Vector2.ZERO)
		for point in poly:
			box = box.expand(point)
		box = box.grow(runner_radius)
		polygons.append(poly)
		boxes.append(box)
		envelope = box if i == 0 else envelope.merge(box)
	return {"polygons": polygons, "boxes": boxes, "envelope": envelope, "circle": circle,
		"radius": radius, "poses": poses, "offset": det.watch_offset_cells * CELL_PX,
		"runner_radius": runner_radius}

# Does the runner's detection circle at `world` overlap pose i's vision?
static func _covers(shapes: Dictionary, i: int, world: Vector2) -> bool:
	var box: Rect2 = shapes["boxes"][i]
	if not box.has_point(world):
		return false
	if shapes["circle"]:
		var pose: Dictionary = shapes["poses"][i]
		var center: Vector2 = pose["pos"] + Vector2(shapes["offset"], 0.0).rotated(deg_to_rad(float(pose["facing"])))
		return center.distance_to(world) <= shapes["radius"] + shapes["runner_radius"]
	var poly: PackedVector2Array = shapes["polygons"][i]
	if Geometry2D.is_point_in_polygon(world, poly):
		return true
	for j in poly.size():
		var a := poly[j]
		var b := poly[(j + 1) % poly.size()]
		if Geometry2D.get_closest_point_to_segment(world, a, b).distance_to(world) <= shapes["runner_radius"]:
			return true
	return false

# Chance the runner is seen crossing the covered stretch at `speed`, over
# evenly spaced phases of the signal's cycle.
static func _hit_chance(layout: FacilityLayout, shapes: Dictionary, pose_count: int, intervals: Array, speed: float) -> float:
	if pose_count <= 1:
		return 1.0
	var start: float = intervals[0]["from"] - ROUTE_STEP
	var finish: float = intervals[intervals.size() - 1]["to"] + ROUTE_STEP
	var duration := (finish - start) / maxf(0.001, speed)
	var hits := 0
	for k in PHASES:
		var phase := float(k) / float(PHASES) * pose_count * POSE_DT
		var t := 0.0
		while t <= duration:
			var point := layout.sample_position(start + t * speed)
			var world := Vector2(point.x * CELL_PX, point.y * LANE_PX)
			var index := int((phase + t) / POSE_DT) % pose_count
			if _covers(shapes, index, world):
				hits += 1
				break
			t += POSE_DT
	return float(hits) / float(PHASES)
