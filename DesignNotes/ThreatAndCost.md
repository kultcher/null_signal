# Threat and Cost

How we measure what an obstacle asks of the player, so levels can be checked
while authoring and, later, generated. Two halves:

- **Threat** - can this signal hurt the runner, where, how reliably, and how
  much warning does the player get? Computed statically from authored data
  (`ReachAnalyzer`).
- **Cost** - how long does it take a person to deal with it? Measured from
  playtests, not simulated (`CostTable`, filled by gauntlet telemetry).

A level is then a sequence of threats, each with a decision window, and a cost
to clear. Comparing the two tells us whether an obstacle fits, is tight, or
forces a hold - which is the raw material for pacing and proc-gen.

## Design stance

- The first question is binary: **can this obstacle threaten the runner at
  all?** Exact timing matters less; mobile obstacles and speed changes blur it
  anyway.
- A threat that can never land still does work: the player doesn't know it's
  harmless. "Never" signals are tension props, and that's a legitimate use. The
  analyzer just makes it a choice rather than an accident.
- Time cost is a human number. Puzzle and IC solve times depend on skill,
  familiarity and attention split; we measure them (test gauntlet) and keep the
  table honest about which entries are still guesses.

## Threat model (ReachAnalyzer)

`Scripts/Analysis/ReachAnalyzer.gd`. Static; builds no gameplay nodes.

For each signal it replays the authored behavior for exactly one cycle (vision
sweep schedule, patrol movement including dwells) at 0.1s steps, using the
same `DetectionComponent.get_visual_polygon()` as gameplay, and tests the
runner's route (sampled every 0.05 cells of path) against each pose. The
runner counts as touched when the route point is inside the polygon or within
the runner's detection radius of its edge (24px: the 60px circle under the
RunnerTeam 0.4 scale).

### Report fields

| Field | Meaning |
| --- | --- |
| `kind` | `watcher` (vision raises heat / harms), `blocker` (locked door), `none` |
| `reach` | `certain`, `possible`, `never`, `open` (unlocked door), `n/a` |
| `intervals` | route stretches it covers: `from`/`to` in path progress, `from_cell`/`to_cell`, `max_ratio` = max fraction of its cycle any point there is watched |
| `hit_walk` / `hit_hustle` | chance a runner passing at base speed / hustle is seen, over 24 evenly spaced phases of the signal's cycle |
| `interact_progress` | first route point where the player can see and touch it (on screen and within interaction range) |
| `threat_progress` | first route point it can threaten |
| `window_walk` / `window_hustle` | seconds between the two: the **decision window**. Negative = it threatens before it can be touched |
| `consequence` | text summary of `ResponseComponent` effects (heat/s, damage, stop) |
| `cycle_sec`, `mobile` | behavior cycle length; whether it patrols |

Reach classes:

- **certain** - some route point is watched at every moment of the cycle. You
  cannot walk past it unseen; it must be dealt with (or tanked).
- **possible** - coverage depends on timing. Hit chance says how often a
  walk-through gets caught. A 100% walk chance on a "possible" signal means no
  single point is always watched, but you can't slip through at walking pace.
- **never** - vision never touches the route. Tension prop.
- Doors: a locked door is a certain blocker at the point the route meets it.

### Validation

The intervals were checked against a physics replay of the tutorial (runner
walked through, contacts logged): cam_01 3.42-4.57 vs 3.40-4.60 cells, door_01
6.2-6.8, cam_07 34.4-35.6. cam_04 is "never" and is never hit in play.

### Known simplifications

- **Hit chances are phase-uniform estimates.** They assume the runner arrives
  at a random point in the signal's cycle. In play, signals start their clocks
  when they spawn on screen, so a given run is closer to deterministic: in
  repeated replays drone_02 (54% predicted) was never hit. Treat hit chance as
  "how much this depends on luck/timing", not a literal probability.
- Alerts, investigation and escalation spawns are ignored.
- Runner holds and hustle mid-pass aren't modelled (only constant walk/hustle).
- Walls don't block vision (they don't in gameplay either).
- **Possible gameplay bug:** with `follow_movement_facing`, a mobile signal's
  facing equals its movement angle, but the cone polygon is built pointing to
  -x, so the cone trails behind the patroller. The analyzer reproduces gameplay
  as-is. Worth a look before tuning patrol threats.

## Cost model (CostTable)

`Resources/Analysis/cost_table.json`, loaded by `Scripts/Analysis/CostTable.gd`.

Each entry is seconds split into:

- **blocking** - the player's attention is tied up (puzzle open, choosing a
  command). Can't overlap other blocking work.
- **background** - runs on its own (scan layers, a reboot timer). Can overlap
  the runner's walk and other work.

Every entry has `source` (`code`, `guess`, `telemetry`), `samples`, and
`notes`. The table starts with code-derived scan times and guesses for
everything else; telemetry replaces guesses entry by entry.

Components:

| Section | Keys |
| --- | --- |
| `base` | `scan_identity` (0.25s), `scan_access` (0.5s), `scan_ic_layer` (0.5s per module or "IC: None"), `notice`, `connect`, `command` |
| `puzzles` | `sniff`, `decrypt`, `fuzz`, each keyed by difficulty `"1".."4"`; past the end uses the last row |
| `ic` | by codex id without `codex_`: bouncer, callback, faraday, haze, trace, reboot, tripwire, siphon, heartbeat, tether, shy, necromancer. Flat entries or keyed by difficulty |
| `unknown` | fallback; counted in `estimate().unknown` so gaps are visible |

`CostTable.estimate(data)` sums: scan layers; then, for anything engageable
(hackable, puzzle or IC), notice + connect + command + puzzle (by type and
difficulty) + each IC module (by codex id and `base_difficulty`). It returns
the totals, an item breakdown, and how many items are still guesses.

`CostTable.fit(estimate, report, hustle)` compares against the decision window:

- `fits` - total cost <= window
- `tight` - only the blocking part fits; background has to overlap the walk
- `hold` - the runner has to wait `hold_sec`
- `preemptive` - window is negative: it must be handled from further back, or
  the runner waits
- `no threat` - reach is never/open/n-a

### Counterplay (not costed yet)

A threat can be answered by solving it, or by bypass: blinding/looping a
watcher, timing a walk past a possible watcher, hustling, holding, or tanking
the heat. Only "solve" is costed now. Later entries could cost bypass routes
(e.g. hold cost = time until the patrol leaves) so the generator can choose the
cheapest answer the player is likely to take.

## Level viewer

Threat toggle (F2 viewer): route bands per signal (red certain, amber possible
with alpha by coverage), reach rings on signals (grey = never, possible shows
walk hit %), status-line totals, and inspector sections THREAT // REACH and
COST // ESTIMATE with fit at walk and hustle. Analysis runs on load/reload
(~0.25s for Night Audit) using the live TimelineManager speed, hustle,
interaction-range and screen settings.

## Telemetry contract (for the test gauntlet)

The gauntlet records what people actually do; summaries update the cost table.
Proposed format: one JSON object per line (JSONL), one file per session, in
`user://telemetry/<session_id>.jsonl`.

Common fields on every event:

```json
{"t": 12.34, "event": "scan_started", "session": "2026-10-10T14-03-11", "run": "gauntlet", "signal": "cam_03", "sig_type": "CAMERA", "runner_progress": 18.2, "speed_mode": "walk"}
```

- `t` - seconds since run start (game time, pausable time excluded)
- `signal` - system_id; omit for run-level events
- `speed_mode` - walk / hustle / hold

Events:

| Event | Extra fields |
| --- | --- |
| `run_started` / `run_ended` | `result` (complete, burned, quit), `heat`, `tester` |
| `signal_visible` | first frame the signal is on screen |
| `scan_started` / `scan_layer_complete` / `scan_complete` | `layer` (IDENTITY, ACCESS, IC), `layer_index` |
| `connected` / `disconnected` | `reason` (player, bouncer, range, ...) |
| `connection_ready` | connection reveal finished; emitted before buffered command dispatch |
| `command` | `command`, `ok`, `blocked_by` (IC id, if any) |
| `puzzle_opened` / `puzzle_solved` / `puzzle_failed` / `puzzle_closed` | `puzzle` (sniff/decrypt/fuzz), `difficulty`, `attempts` |
| `ic_triggered` / `ic_neutralized` | `ic` (codex id without prefix), `difficulty` |
| `detected` | `by` (system_id), `heat_delta` |
| `hold_started` / `hold_ended` | runner held |
| `signal_resolved` | `how` (disabled, looped, unlocked, bypassed, ignored) |

Derived per signal, per tester:

- **blocking time** = sum of puzzle open-to-close + IC interaction time +
  connection reveal time (`connected` to `connection_ready`) + command work
  (measured from `connection_ready` to the first command). Callback interaction
  also starts at readiness, so the reveal is counted once.
- **background time** = scan_started to scan_complete, minus blocking overlap.
- **notice** = `signal_visible` to first `scan_started`.
- **hold** = time held while this signal was the active target.

Updating the table: a summary script groups by key (`puzzle.sniff.2`,
`ic.callback`, `base.command`, ...), writes the median to `blocking` /
`background`, sets `source` to `telemetry` and `samples` to n, and keeps the
spread (p25/p75) in `notes` or extra fields. Keep guesses for keys with fewer
than ~5 samples. Record tester skill tags so we can split novice/expert later.
The gauntlet summary calibrates shared base costs from unprotected baseline
trials only. Puzzle/IC costs retain their resolved tuning signatures. Older
logs without `connection_ready` cannot separate reveal and command/Callback
time, so those cost candidates are excluded rather than double-counted.

## Pressure curve

Per section (and whole run), plot over route progress:

- threats per stretch, weighted by reach (certain 1.0, possible = hit chance)
- sum of cost estimates vs. available walk time
- holds forced by `fit`

Goals for authored levels: ramp in, a peak per section, a breather at section
transitions (the relay remap is a natural one), and no stretch where forced
holds stack. The viewer can draw this as a strip under the map once the cost
numbers are trustworthy.

## Encounter templates and proc-gen

Building blocks for generation are **encounters**, not single signals: a small
group with a role and a known threat/cost signature. Examples:

- *Gate*: locked door (certain blocker) + a camera watching its approach
- *Sweep corridor*: one sweeping camera, possible reach, low cost, skill check
  on timing
- *Patrol room*: mobile watcher crossing the route, possible reach, bypass by
  waiting
- *Locked terminal*: puzzle-gated info signal that unlocks a later shortcut
- *Tension prop*: a never-reach watcher placed for mood

Pipeline:

1. Pick environment blocks (rooms/props, `environment_blocks.md`) and a target
   pressure curve.
2. Place encounter templates along the route with parameters (difficulty, IC,
   sweep timing).
3. Run `ReachAnalyzer` + `CostTable.fit` on the result.
4. Reject or repair placements that break the curve (stacked holds,
   preemptive certain threats with no counterplay, accidental "never"
   threats where a real one was intended).
5. Add flavor objects.

## Roadmap

1. Done: ReachAnalyzer, cost table framework, viewer Threat overlay, tests.
2. Gauntlet + telemetry recorder (Codex), using the contract above.
3. Summary script: telemetry JSONL -> cost_table.json.
4. Pressure strip in the viewer.
5. Bypass costs (hold-until-clear, hustle-through).
6. Encounter template resources and a first generator pass on one block type.

## Tests

`res://Tests/threat_analysis_test.tscn` - tutorial cam_04 never, cam_01 certain
over 3.4-4.6, Night Audit never-list, cam_records certain with a positive
window, analysis time, cost estimates sum and cover every puzzle/IC, fit
verdicts.
