# Disruptive IC

Lag, Spammer, Degrade, Blackout, Glitch and Redact are registered with the
existing `RunDefinition` builders and have Codex entries. Their runtime owner
is `SessionDisruptionController`, a child of the terminal. A session starts
when its tab opens, not when its connection animation finishes. Effects keep
running when another tab is selected. Closing the tab, losing the connection,
disabling the host, or freeing the run removes its effects. Re-enabling a host
whose tab is still open starts a fresh effect lifetime.

## Testing and tuning

Run `Scenes/Tests/disruptive_ic_lab.tscn` (F6). The runner starts stopped.
Choose any combination in the Tuning panel, optionally add Callback and a
puzzle, then press **Apply / fresh host**. Connect to the host and try commands,
other tabs, fake Glitch clicks and disconnect/reconnect. The neighbor signals
make Blackout visible. **Runner: move / stop** enables ordinary approach and
door contact. **Apply** restores health, heat and fresh puzzle/IC instances.

All six module resources are also exported on the lab root for Inspector
tuning. The in-game panel exposes their tuning fields; edits apply when a
fresh host is created. The lab reveals scan details for convenience and
disables escalation and automatic Codex popups.

The encounter gauntlet is intentionally unchanged while its template
integration is in progress. These IC can be added through ordinary builders
without coupling that work to the old single-door selection UI:

```gdscript
spawn(BASIC_DOOR, 4.0).id("disruptive_door") \
    .add_ic_custom("lag", {"delay_sec": 0.4}) \
    .add_ic_custom("redact", {"letter_fraction": 0.3}) \
    .add_puzzle("decrypt", 2)
```

Use `add_ic(name, difficulty)` for the initial five-tier presets. Higher tiers
currently clamp to tier five, matching the other existing IC profiles.
`add_ic_custom` fixes explicit tuning against escalation. Saved module `.tres`
resources can also be put directly into an `ICComponent`.

| IC | Custom parameters | Behavior |
| --- | --- | --- |
| Lag | `delay_sec` | Every keyboard event, including edits, shortcuts and Enter, is buffered for this host. Native Godot editing runs in an isolated input viewport; only its output is mirrored to the displayed command line. Multiple commands retain their order. Pending input continues on background tabs, waits for connection readiness, and is discarded on disconnect. |
| Spammer | `placement` (0 timeline, 1 terminal, 2 both), `spawn_interval_sec`, `max_popups`, `popup_size` | Closable popups obstruct clicks without taking keyboard focus. The count limit is per host; closing a popup permits a replacement at the next spawn interval. Disconnect removes that host's popups. |
| Degrade | `ramp_sec`, `max_corruption`, `noise_interval_sec` | Noise ramps from zero to the configured fraction. Both history and input have a separate display representation. Commands, clipboard text, BBCode and stored history remain intact. Reconnect resets the ramp. |
| Blackout | none | Hides all signal pictures, tooltips and session lines while any Blackout host is connected. Runner, corridor, terminal and physical detection keep working. Known IDs still work in terminal commands. Closing one host does not clear another host's Blackout. |
| Glitch | `position_count` (includes the real position), `jump_interval_sec`, `max_offset_px` | Cycles the host's visual image and pointer target. A solid cyan pip marks the real phase; fake phases have a hollow pip. Fake clicks ripple without connecting, scanning or pinning a tooltip. The real entity, interaction distance and detection collision shapes never move. It starts on connection and restores the true picture on disconnect. |
| Redact | `letter_fraction` | A stable mask replaces individual letters in the host's security descriptions, detail tooltip, terminal detail panels and output prompts. Digits, punctuation and BBCode remain intact. User command echoes are not censored. The actual `$Callback` return token is explicitly protected, including special characters. |

Redact and Degrade compose without hiding the actual Callback challenge:
the output return token stays readable under both effects. Degrade can still
obscure the player’s input display, without changing the submitted value.
Redact does not censor user input. New Glitch sessions begin at their real
position and then cycle; switching tabs does not restart them.

## Shared UI and recorder integration

The terminal retains canonical display text in `_history_source` (including
transient output) and canonical persistent lines in `TerminalSession.history`.
The controller transforms only their presentation. Scripted system dumps and
Null Spike animations suspend the IC text overlay while they own the terminal.
Delayed Enter and the older connection-reveal buffer both capture the original
host, rather than using whatever tab happens to be visible on delivery.

The controller exposes `effect_event(sig, effect, event, details)` for telemetry:
`started`, `ended`, Lag `queued`/`submitted`, Spammer `spawned`/`dismissed`, and
Glitch `fake_clicked`. The host signal is explicit for attribution with several
sessions open. The recorder's existing resource serialization can capture all
exported tuning values. Hooking these friction events and exposing the new
types in the encounter gauntlet is deferred to that integration; no numeric
attention-cost guesses have been inserted into the cost table.

## Validation

`Tests/disruptive_ic_test.tscn` drives real keyboard events, native delayed
editing, command dispatch, session switches, mixed IC, the connection reveal,
cleanup and the standalone lab. It checks preserved source text, Callback
readability, popup placement/caps, Blackout ownership and unchanged Glitch
detection/range. Run it headlessly alongside `regtest`, `ictest`,
`calibration_gauntlet_test` and the viewer/restart tests when changing shared
terminal code.

## Signal display blocks

Several systems hide parts of a signal for their own reasons: unrevealed
guards, Blackout, Glitch decoys, and later section previews or cutscenes.
They must not write `visible`, `signal_icon.input_pickable` or
`tooltip_main.visible` directly, or they undo each other (unrevealed guards
used to show their tooltips because the disruption update reset them every
frame). Instead each system sets or clears its own reason:

```gdscript
entity.set_display_block(&"my_reason", entity.BLOCK_TOOLTIP | entity.BLOCK_PICK)
entity.set_display_block(&"my_reason", 0)   # clear
```

`BLOCK_VISIBLE` hides the whole entity (and implies the other two),
`BLOCK_PICK` stops clicks and hover, `BLOCK_TOOLTIP` hides the tooltip.
`signal_entity._apply_display()` combines all reasons. Current reasons:
`hidden_guard`, `blackout`, `glitch_decoy`.

`SessionDisruptionController` pushes visuals only when a signal's disruption
state changes (and on session open/close), and does nothing while no
disruption session is active.
