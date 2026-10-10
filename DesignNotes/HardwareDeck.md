# Hardware Deck (prototype)

The player's deck as physical hardware: a main deck along the bottom of the screen and
hot-swapped aux modules that cable into its expansion port while a puzzle is running.

## Pipeline

1. `Tools/Blender/build_deck.py` builds the hardware procedurally and renders it with a
   pixel-exact orthographic camera (1 Blender unit = 100 px):
   - `Visuals/Deck/<name>.png`: beauty render, transparent background
   - `Visuals/Deck/<name>_albedo.png` and `<name>_normal.png`: for 2D normal-mapped lighting later
   - `Visuals/Deck/<name>.json`: screen / lamp / port / slot rects in image pixels
   Run from the project root: `blender -b -P Tools/Blender/build_deck.py`
   (options: `-- --fast`, `-- --gpu`, `-- --only deck_main`, `-- --samples 32`, `-- --scale 2`)
2. Godot reads the JSON, so screens and indicators always sit on the rendered hardware.
   Change a layout number in the script, re-run, and Godot follows.
3. With no renders present, every device draws a flat placeholder from the same numbers
   (`DeviceShell.FALLBACK_META`), so layout work does not wait on Blender.

Devices: `deck_main` (1860x440 chassis), `aux_decrypt` (480x430), `cartridge` (74x106).

## Code

| Script | Role |
|---|---|
| `Scripts/Deck/device_shell.gd` (`DeviceShell`) | Art + shadow, screen slot hosting any Control, glass overlay, power on/off, drag / lift / snap / double-click home |
| `Scripts/Deck/main_deck.gd` (`MainDeck`) | Lamps (`set_lamp`), heat gauge (`set_heat`), RAM LEDs (`set_ram`), header/status strips, program cartridges |
| `Scripts/Deck/desk_layer.gd` (`DeskLayer`) | Owns deck, cables and aux modules. `dock_content(control)` plugs a puzzle into a new module; it unplugs itself when the puzzle is freed |
| `Scripts/Deck/deck_cable.gd` (`DeckCable`) | Patch cables between metadata points |
| `Scenes/Deck/deck_test.tscn` | Standalone test: F2 decrypt, F3 sniff, F4 heat, F5 IC lamp, Esc unplug |

## Lighting and decals

- Each device's art is a `CanvasTexture` (beauty render + `<id>_normal.png`), lit by 2D lights on
  light layer 2. Only chassis art and decals sit on that layer, so screen UI text is never tinted.
- Lights: screen spill (DeviceShell, fades with power on/off), lamp glow (colour/energy follow
  `set_lamp`, ALERT pulses), header/status amber spill, RAM glow, and a heat light that tracks the
  lit length of the gauge.
- DeskLayer runs on CanvasLayer **layer 0**: in testing, 2D lights did not reach items on a non-zero
  CanvasLayer. Layer 0 still draws over the main scene canvas and under WindowManager (layer 1).
- Decals: `Visuals/Deck/Decals/` holds stickers cut from `Visuals/ModuleBits` sticker sheets.
  `DeviceShell.add_decal(tex, center, scale, rotation)`; MainDeck places a default set
  (`default_decals`, `decorate`).

## Screen budget (1920x1080)

- Facility map: y ~43-600 in map mode (it is taller than the old strip).
- Escalation panel: clamped to sit just above the deck (y ~546) when the hardware is active.
- Deck: 1500 px wide, centred (chassis x 210-1710, y 640-1080). Terminal glass 760x314,
  about 77 columns and 10 lines in MainTheme.
- Aux module dock 1 sits over the deck's right column (x 1316); docks 2-3 are over the map.

## In the game (wired)

`run_main.tscn` has a `DeskLayer` node and `WindowManager.use_hardware_devices = true`.
To switch back to the old UI: untick `use_hardware_devices` and delete/disable `DeskLayer`.

What the deck does in-game:
- Adopts `WorkspaceAnchor/TerminalWindow` onto the main screen; hides its Scan/Lock/IC row.
- Lamps mirror the terminal's detail panels (`terminal_window.detail_panel_refreshed`), with
  progress bars for scan / IC. The LOCK lamp is clickable when the lock is actionable and opens a
  SNIFF / DECRYPT flyout (same as the old toolbox).
- Heat gauge + status LCD from `GlobalEvents.heat_state_changed` / HeatManager max heat.
- RAM LEDs from `RAMManager.ram_usage_changed`.
- Program cartridges from `ProgramManager` (left click load/use, right click eject; seated =
  loading/running/cleanup with a progress strip).
- Puzzles plug into aux modules (WindowManager `_puzzle_started`).
- ObjectiveTracker lives on the deck's secondary screen (hidden while aux dock 1 is occupied).
- HeatTracker and ProgramDock are hidden (`hide_when_active`).
- Tutorial: heat focus targets the deck gauge; map-mode dialogue docks at
  `WindowManager.hardware_dialogue_position` (default 1500, 60).

Edits to existing scripts: `terminal_window.gd` (signal), `window_manager.gd` (hook, dialogue
position, `is_hardware_active()`), `tutorial_manager.gd` (heat focus, dialogue position),
`escalation_manager.gd` (clamp above deck).

## Next

- Wire lamps to the terminal's Scan / Lock / IC state (the in-screen detail row is hidden on the deck)
- Move session tabs into the header strip (+1-2 terminal lines)
- Sniff gets its own module model; cartridges driven by ProgramManager / RAMManager
- Normal-mapped lighting from the albedo/normal passes (alarm strobes, heat glow, null spike flash)
- Facility map as a "viewing tablet" bezel
