# Calibration gauntlet

Open `res://Scenes/Tests/calibration_gauntlet.tscn` and run the scene (F6).
Choose a tester and experience tag, select element pools and tier ranges, then
start. Settings can be reopened during play; they pause the session and apply
to the next signal. The current trial keeps its recorded configuration.

The corridor contains one door at a time, spawned just beyond the right edge.
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

The door pool includes Bouncer, Callback, Faraday, Haze, Trace, Shy and Siphon.
Reboot, Heartbeat and Tripwire depend on disabling their host, which OP does not
do. Tether and Necromancer need other targets or a different host. Those need
separate scenarios rather than misleading door measurements. Siphon currently
adds heat, despite the older cost-table description referring to RAM.

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

The recorder logs scans and layers, connection, commands and rejections, puzzle
open/solve/close, input errors, Fuzz impacts, IC triggers, Callback acceptance,
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

Only unassisted successful isolated trials feed cost candidates. Puzzle
open-to-solve and Callback connection-to-acceptance are measured separately;
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
real breach and pause, Callback retry/acceptance, Fuzz, and the JSONL contract.
