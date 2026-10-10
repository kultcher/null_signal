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
| Left click on a signal | Inspect ID, exact cell/lane, vision, patrol, and IC |
| Shift+left click twice | Place ruler A and B (snaps to nearby signals); next click starts a new ruler |
| Delete | Clear ruler |
| R / Reload | Re-read the selected run script and rebuild the preview |

Use the run dropdown to inspect any `.gd` in
`Resources/RunData/AuthoredRuns`; this does not switch the live game to that run.
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

Route, Vision, Patrols, Sections, and Signal labels can each be toggled.
Hidden and unscanned authored signals are always included. Vision uses the
same polygon function as gameplay; sweep cameras display their initial sweep
orientation, with the sweep schedule in the inspector. Patrols are static paths,
including the return leg for loop patrols. Walls retain their gameplay rendering
behavior and remain decorative.

## Authoring and reload

Edit and save the selected run's `.gd`, then press R. Reload preserves the
view, selected section ID, and selected signal ID where they still exist.
Parse failures, missing files, and unrelated scripts keep the previous valid
preview and display an error status. Detailed parse errors appear in Godot's
output. The viewer requires a valid `RunDefinition`; arbitrary runtime errors
inside authored getter methods are still GDScript errors and should be fixed
in the source.

The viewer is a separate authored snapshot. Reload updates **the preview**;
restart the run to play the new definition. Closing resumes the existing run
at its frozen position. It does not reset progress, heat, scans, terminals, IC,
or patrols.

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
godot --headless --path . res://Tests/regtest.tscn
```

The invalid-reload variant deliberately emits a parse error and verifies that
the old snapshot remains usable. For screenshots, run the viewer test with the
Compatibility renderer on a display with CPU software rendering:

```sh
NULL_VIEWER_SHOT_DIR=/tmp LIBGL_ALWAYS_SOFTWARE=1 godot --path . --rendering-method gl_compatibility --audio-driver Dummy res://Tests/level_viewer_test.tscn
```

Set `NULL_VIEWER_SHOT_DIR` to an existing writable directory to save parking and
office captures there. Otherwise the test does not write screenshots.
