# Future Directions

Ideas discussed and parked for later. Not commitments; each lists the open
questions to settle before building.

## Runner stop / hold

Feedback: players may want to hard-stop the runner, especially around hazards
(a runner won't walk into an active crusher). The tension: the runner never
stopping is the game's core time pressure, and the threat model's decision
window assumes it. An unlimited stop makes every window infinite.

Directions, roughly in order of preference:

1. **Obstacle-owned stops (diegetic).** Hazards behave like locked doors: the
   runner stops at the edge on his own and waits. Pressure comes from where he
   stops being exposed (watchers sweeping, loitering heat, a breach-style
   timer). Stop-and-go rhythm is a property of the obstacle, not the script.
   Fits the analyzer: a hazard is a blocker with a cycle.
2. **Player hold with an irregularity meter.** Free for a short grace period
   (2-3s, enough to let a sweep pass), then heat ramps: a stationary person in
   monitored space is irregular. Show it as a visible meter on the runner.
   Cheap experiment: slow (0.5x) already exists; log hold use in the gauntlet.
3. **Cover points.** The runner can only hold at relay-marked cover (alcoves,
   pillars, crates, doorways). Makes the stop a level-design tool; cover
   density becomes a proc-gen difficulty dial; the analyzer measures the window
   to the next cover point instead of to the threat. Irregularity meter can
   still apply once the grace period ends.

**Null Spike:** keep as the panic button (global slow). A full time stop
changes the role from operator-under-pressure to pause-and-plan and freezes
the puzzles being solved. A stronger slow is a cheap knob but doesn't answer
the hazard case.

## Section preview at safe entries

The runner holds between major sections; the relay remap becomes the start of
a preview of the next area. Fiction: "I'm hidden here; once I'm in, I keep
moving." The relay can map structure and pick up device noise but is out of
range to connect.

- **Information tiers** (relay upgrade hook): layout + route; + signals as
  UNKNOWN blips; + patrol routes / sweep arcs.
- **Ending it:** player presses go, maybe with a soft cap. Nothing can be
  hacked, so a long look only costs time; planning is the point.
- **Marking:** tag blips during the preview so scans start as soon as they're
  in range. A head start without breaking "can't touch it yet".
- **Section property `entry: safe | hot`.** Safe = hold + preview. Hot = dropped
  straight in (elevator opens on a guard); hot entries become a deliberate
  design beat.
- **Cover points are the same mechanism at small scale:** section break = full
  hold + whole-area preview; cover point = short hold + next-room preview, then
  the irregularity meter.
- **Proc-gen:** every generated section gets a read moment, so generated
  layouts can be harsher without feeling unfair. Also a built-in breather in
  the pressure curve.
- **Implementation:** reuse the level viewer's projection (fit section, zoom)
  and the map layer's preview mode in-game, with signal details hidden.

Done: sections have an `entry` field (`hot` / `safe`, not acted on yet) and
encounter instances carry stop points (see `EncounterTemplates.md`), so either
direction can be added later.

## Gauntlet expansions

Done (see `CalibrationGauntlet.md`): encounter trials, cadence, window sweep,
predicted cost per trial, exposure counts, sticky tester, camera host for
Reboot / Heartbeat / Tripwire, felt-difficulty rating, warm-up flag and
session index. Watcher-only bypass behavior is observable through camera
corridor encounters (holds, speed and heat are logged per encounter).

Collection: isolated mode, tiers 1-2, ~5 samples per key (~125 trials, 2-3
sessions); encounters and window sweeps after that.
