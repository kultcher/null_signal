# Fuzz prototype

Open `res://Scenes/Tests/fuzz_test.tscn` and run the current scene (F6).
Move the mouse around the core to aim the data cannon; left-click once per
packet. When unfocused, the first click activates the puzzle without firing.
Packets already in flight, regeneration, feedback fading, and optional decay
continue while unfocused. Clicking a tuning field or the bottom text field
lets you test this behavior.

The tuning panel exposes packet budget, regeneration, flight time, scoring,
decay, impact width, and feedback timing. Use **Apply + restart** to try the
current values. These controls change the test instance, not saved resources.
The target angle can be fixed for repeatable tests (-1 randomizes it). The
reveal toggle shows the target arc only in the lab. A solved puzzle stays open
in the lab so you can inspect it and restart.

## Defaults

| Setting | Value |
| --- | --- |
| Starting packets / capacity | 5 / 5 |
| Regeneration | 1 packet per second |
| Packet flight | 0.5 seconds |
| Sweet spot | Stationary, random 30-degree arc |
| Points throughout sweet spot | 20 |
| Falloff outside sweet spot | 2 points per 5 degrees, smoothly interpolated |
| Points to solve | 100 |
| Progress decay | 0 points per second |
| Impact color hold / fade | 2.5 / 2.5 seconds |
| Impact mark width | 10 degrees |

Falloff measures distance from the nearest edge of the sweet spot. With the
defaults, an offset of 15 degrees from its center earns 20 points, 20 degrees
earns 18, and 65 degrees or more earns zero. Impact marks range from red at full
points through orange to yellow, then fade back to the default white core.
Regeneration does not accumulate credit while ammo is full.

## Resources and difficulty

Create a `FuzzPuzzleConfig` resource, or duplicate
`res://Resources/PuzzlePrefabs/fuzz_default.tres`. All gameplay numbers and
feedback colors are editable in the Inspector. The lab root also accepts a
config resource, starting difficulty, fixed target angle, and reveal setting.
Runtime settings are copied and normalized without modifying authored assets.

`higher_difficulty_profiles` accepts complete `FuzzPuzzleConfig` resources for
difficulty 2, 3, and so on. Beyond the list, the last profile is reused. An empty
list uses the base values at every difficulty; no harder balance presets are
assumed yet. Set `decay_points_per_second` on a harder profile to enable decay.
This uses the existing puzzle difficulty and escalation path. A profile is
selected when the puzzle opens; escalation does not alter shots mid-puzzle.

Authored run builders support both forms:

```gdscript
.add_puzzle(&"fuzz", 1)
.add_puzzle_custom(&"fuzz", {"config": preload("res://Resources/PuzzlePrefabs/fuzz_default.tres")})
```

Custom puzzles default to fixed difficulty, like the existing custom puzzles.
Pass `"uses_escalation_difficulty": true` to use escalation, and `"difficulty"`
to choose their initial profile. `RunDefinition.make_fuzz_puzzle(difficulty,
config)` also accepts a custom resource directly.

In gameplay, `RUN FUZZ` opens this puzzle on a connected Fuzz-locked signal.
Reaching the configured point target unlocks that signal and closes the window
through the existing puzzle lifecycle. Preview security inspection includes
the effective Fuzz settings.

## Automated checks

Run `res://Tests/fuzz_puzzle_test.tscn` for scoring boundaries, ammo and timing,
decay, feedback, resource profiles, focus restrictions, and the real command
launch/unlock flow. The test exits with a nonzero status if a check fails.
