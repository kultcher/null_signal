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

- Facility map: y 43-343 (unchanged)
- Free band: y 343-640. Aux modules dock here or over the deck's right column.
- Deck chassis: y 640-1080. Terminal glass is 1132x314, about 10 lines with the
  current MainTheme and title bar. Each +22 px of deck height is about +1 line.

## Trying it in the real game

1. Add a `CanvasLayer` named `DeskLayer` to `run_main.tscn` (sibling of `WindowManager`)
   with `desk_layer.gd`. Set `terminal_path` to the TerminalWindow to move it onto the deck.
2. On `WindowManager`, tick `use_hardware_devices`. Puzzles now plug into aux modules.
   WindowManager raises its own layer above the desk so tutorial focus/dialogue stay on top.
3. Not yet handled: ProgramDock and ObjectiveTracker still sit at their old positions under the deck.

## Next

- Wire lamps to the terminal's Scan / Lock / IC state (the in-screen detail row is hidden on the deck)
- Move session tabs into the header strip (+1-2 terminal lines)
- Sniff gets its own module model; cartridges driven by ProgramManager / RAMManager
- Normal-mapped lighting from the albedo/normal passes (alarm strobes, heat glow, null spike flash)
- Facility map as a "viewing tablet" bezel
