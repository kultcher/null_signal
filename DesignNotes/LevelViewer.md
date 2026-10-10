# Level viewer

Run the game from Godot, then press **F2** to open the debug viewer. F2 or
Escape returns to the live run. The viewer is available in debug builds only.
It pauses gameplay and restores the previous pause state when closed.

## Controls

| Control | Action |
| --- | --- |
| Middle mouse drag | Pan horizontally and vertically |
| Mouse wheel | Zoom around the cursor |
| Home / Fit section | Frame the selected section, including side rooms and patrol points |
| Shift+Home / Fit level | Show all sections and authored signals |
| Page Up / Page Down | Previous / next section |
| Left click on a signal | Inspect ID, exact cell/lane, vision, patrol, puzzle, and IC |
| Shift+left click twice | Place ruler A and B (snaps to nearby signals); next click starts a new ruler |
| Alt+left click | Choose a starting point, snapped to the nearest route segment in the visible section(s) |
| Restart here | Replace the live run with a fresh run using the preview definition at the chosen point |
| Delete | Clear ruler |
| R / Reload | Re-read the selected run script and rebuild the preview |

Use the run dropdown to inspect any `.gd` in
`Resources/RunData/AuthoredRuns`; choosing a run only changes the preview until
you use Restart here.
The section dropdown includes an all-sections overview.

## Distance and overlays

Distance is on by default. The top axis marks **absolute cells** and the left
axis marks **lanes**, with adaptive tick spacing as you zoom. Signal labels show
exact `cell / lane` placement. The cursor readout gives fractional coordinates.
The ruler reports signed horizontal cell difference, signed lane difference,
and direct distance in cell-equivalent units. Direct distance uses the gameplay
lane-to-cell metric captured when loading, and does not change with zoom.
It is not distance travelled along the runner's route. Route waypoints have
cumulative `path` distance labels when both Route and Distance are enabled.

Route, Vision, Patrols, Sections, Signal labels, and Security can each be toggled.
Hidden and unscanned authored signals are always included. Vision uses the
same polygon function as gameplay; sweep cameras display their initial sweep
orientation, with the sweep schedule in the inspector. Patrols are static paths,
including the return leg for loop patrols. Walls retain their gameplay rendering
behavior and remain decorative.

Security shows initial puzzle type, difficulty and lock state, plus configured
IC count. Amber diamonds mark locked puzzles/doors; violet squares mark IC.
The inspector includes puzzle configuration, IC descriptions, tuning values,
and whether difficulty scales with escalation. These are the initial authored
values, including hidden protection, independent of scans and changes in the
frozen live run. No IC hooks run while building the preview.

## Runtime

Runtimes are walking time at the run's base speed (`BASE_CELLS_PER_SECOND`),
with no hustle, holds, doors or dialogue: a floor for how long the level takes.
The section dropdown shows each section's runtime, "All sections" the whole
route, and the status line the level total. Route waypoint labels add the time
to reach that point (`path 31.0  3:27`), as does the Restart-here readout.

Flavor objects draw as grey dots; with Signal labels on (and zoomed in far
enough) their text is printed next to them.

## Authoring and reload

Edit and save the selected run's `.gd`, then press R. Reload preserves the
view, selected section ID, selected signal ID, and chosen start section/segment
where they still exist.
Parse failures, missing files, and unrelated scripts keep the previous valid
preview and display an error status. Detailed parse errors appear in Godot's
output. The viewer requires a valid `RunDefinition`; arbitrary runtime errors
inside authored getter methods are still GDScript errors and should be fixed
in the source.

The viewer is a separate authored snapshot. Reload updates **the preview**;
use Restart here or restart the run normally to play the new definition.
Closing resumes the existing run
at its frozen position. It does not reset progress, heat, scans, terminals, IC,
or patrols.

## Restart from a route point

Alt-click the map to place the green START marker, then click Restart here.
The closest route point uses the same lane-to-cell metric as gameplay. It
retains section, segment and segment fraction, so vertical paths and overlapping
section boundaries work. The selected preview run and successfully reloaded
script are used, even if they differ from the current live run.

This starts a fresh run at that position: health, heat, scans, locks, IC,
terminals, guards, RAM reservations and program cooldowns reset. The equipped
loadout and persistent player data are retained. Pending effects from the old
run are stopped before the replacement scene registers its managers.

Earlier gameplay is not simulated. Signals and patrols start in their authored
initial state. The current tutorial sequence is bypassed and its features are
enabled for free play. Future scripted sequences may require their own debug
start handling; this does not reconstruct objectives or sequence history.

## Implementation

`Scenes/Debug/level_viewer.tscn` composes the viewer UI and two draw layers.
`Scripts/Debug/level_viewer.gd` owns the duplicated authored data, projection,
input, reload, and inspection. `level_viewer_overlay.gd` draws distance and
signal overlays. The existing `facility_map_layer.gd` accepts an optional
preview projection, section list, and signal list; live feed defaults remain
unchanged. The preview never creates `ActiveSignal` or gameplay signal nodes,
and never registers itself with `CommandDispatch`.

## Verification

```sh
godot --headless --path . res://Tests/level_viewer_test.tscn
godot --headless --path . res://Tests/level_viewer_test.tscn -- --invalid-reload
godot --headless --path . res://Tests/level_viewer_restart_test.tscn
godot --headless --path . res://Tests/regtest.tscn
```

The invalid-reload variant deliberately emits a parse error and verifies that
the old snapshot remains usable. For screenshots, run the viewer test with the
Compatibility renderer on a display with CPU software rendering:

```sh
NULL_VIEWER_SHOT_DIR=/tmp LIBGL_ALWAYS_SOFTWARE=1 godot --path . --rendering-method gl_compatibility --audio-driver Dummy res://Tests/level_viewer_test.tscn
```

Set `NULL_VIEWER_SHOT_DIR` to an existing writable directory to save parking and
office captures there. The restart test saves `null-viewer-security.png` with
the same environment settings. Otherwise the tests do not write screenshots.
