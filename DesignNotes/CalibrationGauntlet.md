# Calibration gauntlet

Open `res://Scenes/Tests/calibration_gauntlet.tscn` and run the scene (F6).
Choose a tester and experience tag, select element pools and tier ranges, then
start. Settings can be reopened during play; they pause the session and apply
to the next signal. The current trial keeps its recorded configuration.

Door element mode contains one door at a time, spawned just beyond the right edge.
The runner keeps moving. Contact starts the real door breach window (default
three seconds). Successful OP immediately clears the trial; actual breach fails
it. A breach records runner damage but does not open the normal game-over
dialog; runner health resets for the next trial. Either outcome removes the old signal and schedules a fresh door after one
second. The empty corridor rebases between trials so a session can continue
indefinitely. Escalation is disabled. Heat resets between trials by default;
programs and Null Spike remain available and are logged as assistance. Automatic
codex popups are suppressed for gauntlet signals.

## Controls and sampling

- F7 / Pause: freezes gameplay, puzzles, breach timers and both recorder clocks.
- F8 / Repeat fresh: repeats the last completed combination with a fresh puzzle
  and IC instance. Before the first completion it repeats the current trial.
  An interrupted current trial is recorded as `repeated`, not a failed solve.
- F9 / Skip: records `skipped` and moves on.
- F10 / End + save: ends the session; an active trial is `interrupted`.

Single-element mode shuffles an unprotected baseline, each selected IC at each
tier, and each selected puzzle at each tier. IC count is an on/off switch in
this mode. Combination mode uses exactly the selected number of distinct IC
modules and optionally one puzzle. Small matrices are covered exhaustively;
larger ones draw fresh batches of 512 combinations. The baseline is optional.
The seed reproduces configuration order; solutions and Callback strings stay
fresh. Repeat carries `repeat_of` so it can be distinguished from normal trials.

The door pool includes Bouncer, Callback, Faraday, Haze, Trace, Shy, Siphon,
Lag, Spammer, Degrade, Blackout, Glitch and Redact. Camera hosts also accept
Reboot, Heartbeat and Tripwire: these depend on disabling their host, which OP
does not do to a door. Tether and Necromancer still need separate scenarios.
Siphon currently adds heat, despite the older cost-table description referring
to RAM.

Difficulty ranges reserve tiers 1-20, but existing modules and puzzles still
use their implemented profiles, including clamps and fallbacks. Every trial
stores resolved numerical settings so a nominal tier does not imply new tuning.
The scene's exported `settings` resource also accepts a custom Fuzz configuration
and its higher-difficulty profiles.

## Recorder and Claude's cost table

`PlaytestRecorder` follows `DesignNotes/ThreatAndCost.md` from the threat-analysis
work. It writes flushed JSONL events and a per-trial CSV to `user://telemetry/`.
The HUD shows the full path. Closing the game preserves prior events; abrupt
termination may leave an incomplete trial, which the summary reports separately.

Common fields are `t`, `event`, `session`, `run`, `runner_progress`, `speed_mode`,
and, for signal events, `signal` and `sig_type`. `t` is pause-excluded game time.
Additional `wall_t` is pause-excluded real time: use it for human time cost,
because Null Spike slows game time. Tester, skill and trial identifiers are
included. Signal visibility is measured at the screen edge, not at spawn.

The recorder logs scans and layers, connection and channel readiness, commands
and rejections, puzzle open/solve/close, input errors, Fuzz impacts, IC triggers,
Callback acceptance,
heat, holds, breach, speed, assistance and outcomes. Puzzle reopenings count as
attempts; ordinary input errors count separately. `detected.heat_delta` is zero
at contact; subsequent response heat appears in `heat` events. Completed trial
rows include spawn-to-end, visible-to-clear and interaction-to-clear times,
configuration, friction counts and outcome. Durations on non-success outcomes
are elapsed observations, not successful solve times.

To record ordinary play, add a `PlaytestRecorder` node after the game's managers
and enable `auto_record_visible_signals`. This is opt-in; it does not change the
default run scene. It records visible signals and successful OP/KILL, while
unfinished observations are interrupted on exit. Concurrent heat cannot always
be attributed to one host and stays a run-level event in that case.

Run the standard-library summary tool against one or more sessions:

```sh
python Tools/Calibration/summarize.py /path/to/telemetry --tester tester --skill novice --table Resources/Analysis/cost_table.json
```

It writes `summary.json`, `trials_summary.csv`, `component_costs.csv` and
`ic_overhead.csv` under a `summary` subdirectory, or the directory passed with
`--out`. With `--table`, it also writes `cost_table_candidate.json`, in the
version-1 format accepted by `CostTable`. It never overwrites the canonical file.

Only unassisted successful isolated trials feed cost candidates. Base notice,
connect and command samples come only from unprotected baseline trials, so
puzzle and IC tuning does not fragment or bias those shared estimates. Keep
baseline trials enabled to calibrate those entries.

`connected` marks the start of the terminal connection reveal;
`connection_ready` marks its completion, before any buffered command dispatch.
Base connect measures that interval. Base command starts at readiness, and
Callback readiness-to-acceptance excludes the reveal too. Logs recorded before
this marker was added still contribute puzzle and clear times, but their
connect, command and Callback candidates are excluded with a warning.

Puzzle open-to-solve and Callback readiness-to-acceptance are measured separately;
scan background time excludes overlapping puzzle/Callback intervals. Other IC
receives a descriptive baseline delta with scan time removed, not an invented
blocking/background split. Candidates keep guesses below five samples or when
multiple tuning signatures exist. Generated secrets do not split signatures;
actual tuning does. Filter by tester/skill before comparing experience levels.
Successful clear percentiles have survivor bias: review breach counts and
failure elapsed times alongside them before adopting a cost estimate.

## Verification

```sh
godot --headless --path . Tests/calibration_gauntlet_test.tscn
python -m unittest discover -s Tools/Calibration -p 'test_*.py'
```

The integration scene exercises sampling, OP, parser errors, cleanup, repeat,
real breach and pause, buffered Callback retry/acceptance, Fuzz, the JSONL
contract, and the tutorial's runner-detection reaction.

## Encounters, windows and session hygiene

Added after the first sessions. All settings live in the same panel (the extra
fields are built in code, so the scene is unchanged).

- **Trials: encounter templates.** Each trial spawns a whole encounter from
  `EncounterLibrary` (watched door, camera corridor, drone patrol, guard patrol;
  pick the pool with the checkboxes). Every member signal is still its own
  trial (case key `enc.<template>.<role>...`), grouped under an encounter id.
  The encounter ends when the runner leaves its footprint; members still
  active finish as `passed` (`how`: `seen` or `evaded`). Encounter outcome,
  worst first: `damaged` > `breached` > `heated` > `clean`. Results go to the
  JSONL (`encounter_started` / `encounter_ended`) and `<session>_encounters.csv`.
  Encounter members never feed component costs.
- **Cadence.** With Cadence > 0 the next encounter spawns that many seconds
  after the previous one (real, pause-excluded time), up to 2 at once, placed
  after the earlier footprint. 0 = one at a time.
- **Window sweep.** Spawn distances in cells ahead of the runner (e.g.
  `3, 5, 7`); every case runs at every distance. Trials record `lead_cells` and
  `window_sec`; the summary's `window_curve` gives success rate per distance.
  Blank = screen edge, as before.
- **Camera host.** Element trials on a stationary camera on the route instead
  of a door. Accepts the door IC plus Reboot, Heartbeat and Tripwire (marked
  *). Success = the runner passes it without being seen; otherwise
  `detected`.
- **Prediction.** Each trial stores the CostTable estimate made at spawn
  (`predicted`); the summary's `prediction` rows compare it to observed
  interaction-to-clear time.
- **Exposure counts.** Per tester, per element (`puzzle.sniff`, `ic.bouncer`,
  `enc.camera_corridor`), across sessions, in `telemetry/testers/<tester>.json`.
  Each trial records its counts before it started (`exposure`).
- **Tester memory.** The last tester/skill pre-fill the next session.
- **Warm-up.** The first N trials/encounters (default 3) are flagged
  `warmup`; the summary skips them unless `--include-warmup`. `session_index`
  records order for fatigue checks.
- **Felt difficulty.** F4 / F5 / F6 rate the last finished trial or encounter
  easy / fine / hard (`rating` event); the summary averages ratings per group.
- **Heat attribution.** Detection heat ("Detected by <name>.") is credited to
  that signal's trial even with several active; damage goes to the signal that
  most recently detected the runner.

Summary outputs added: `window_curve.csv`, `prediction.csv`, `encounters.csv`.
Window curves and predictions are separated by host. IC overhead is matched
to a baseline with the same tester, skill, speed, breach window, host and
spawn lead; camera pass time is never compared to a door's OP time.

Verification:

```sh
godot --headless --fixed-fps 60 res://Tests/gauntlet_encounter_test.tscn
```

## Disruptive IC integration

All six new IC are available in the ordinary element pool, alone or combined
with other IC and a puzzle. The IC-count maximum follows the host: 13 for doors,
16 for cameras. Missing selection checkboxes are generated from the eligible
lists in `GauntletSettings`, so future additions do not require scene edits.

For encounter trials, enable **Add selected disruptive IC to one encounter
host**. The selected Lag/Spammer/Degrade/Blackout/Glitch/Redact pool, IC count and
IC tier range then form additions to the template. Single-addition mode tests
one IC/tier at a time; combination mode uses the exact selected count.
**Include original template** adds cases with no added IC. Templates keep
their authored puzzles and IC; puzzle controls are disabled in this mode.
The option starts off, preserving the original encounter behavior.

| Template | Host role receiving added IC |
| --- | --- |
| Watched door | `door` |
| Camera corridor | `cam_fixed` |
| Drone patrol | `drone_1` |
| Guard patrol | `cam_reveal` |

Every template/lead runs at every addition case. Large combination sets use
the same bounded sampler as element trials. Repeat keeps the template seed
and selected IC/tier recipe, while creating fresh module instances. Added IC
replace an existing instance of the same type rather than stacking duplicates.
Cadenced encounters retain separate host sessions and cleanup; a Blackout in
one encounter cannot be cleared by closing another.

`ic_disruption` events include the host signal/trial, `ic`, `difficulty`,
`phase`, and effect details (delay, pending input, popup count/placement, etc.).
`disruption_counts` are included in trial JSONL/CSV and aggregated in encounter
JSONL/CSV and summary reports. Useful entries include `lag.queued`,
`lag.submitted`, `spammer.spawned`, `spammer.dismissed`, and
`glitch.fake_clicked`; session starts and manual disconnects are also recorded.
These counters stay separate from the older `ic_events`, avoiding per-key
inflation of that count.

Encounter metadata includes `added_ic` with resolved profiles and
`ic_host_role`. Summaries keep original templates, different added profiles,
and different host roles separate. Encounter trials still never feed isolated
component cost candidates. Old logs without friction counts remain readable;
host is inferred from `sig_type` when available, otherwise legacy door logs
default to `door`.

F4–F10 remain immediate even with pending Lag input; F7 freezes effect timers
and input delivery along with the recorder clocks.

```sh
godot --headless --fixed-fps 60 res://Tests/gauntlet_disruption_test.tscn
python -m unittest discover -s Tools/Calibration -p 'test_*.py'
```
