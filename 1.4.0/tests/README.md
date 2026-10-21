# Headset-free checks

Run commands from the `1.4.0` project directory. These scenes use the production
controller, pickup, voxel, save/load, and menu code. Save/load fixtures are stored
in `/private/tmp/abccad-*`, separately from normal saved builds.

## Automated regressions

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --xr-mode off \
  --path . --scene res://tests/regression.tscn --quit-after 2400
```

The suite uses Godot XR positional trackers with controller poses and input
values. Spawn/recolor buttons and grip/release go through real controller and
XR Tools logic. It also directly calls pickup methods for precise transfer and
undo/redo checkpoints. It covers every block type from both hands, signal
connection idempotence, new/legacy saves, nearby block ownership, loaded
footprints, corrupted saves, held-block cleanup, and menu dispatch/retry.
Look for `REGRESSION RESULT` and an exit code of zero. The installed Godot 4.5.1
may print `p_tracker.is_null()` on shutdown with XR disabled; this is an engine
shutdown warning, not a test verdict. A timeout, script error, or missing result
means the suite did not complete.

## Desktop menu preview

```sh
/Applications/Godot.app/Contents/MacOS/Godot --xr-mode off --path . \
  --scene res://tests/menu_preview.tscn --resolution 1280x768 \
  --rendering-method gl_compatibility
```

Use ordinary mouse clicks to test the actual save/load UI. To render both screens
automatically and quit, append `-- --capture`; PNGs are written to
`/private/tmp/abccad-menu-main.png` and `/private/tmp/abccad-menu-load.png`.

## Official Meta XR Simulator on this Mac

The installed runtime is Meta XR Simulator 71.0.0. Select it for just this
process (no global runtime changes):

```sh
XR_RUNTIME_JSON=/opt/homebrew/Cellar/meta-xr-simulator/71.0.0/meta_openxr_simulator.json \
  /Applications/Godot.app/Contents/MacOS/Godot --path . --xr-mode on \
  --rendering-driver vulkan --max-fps 60 -- --opaque
```

`--opaque` keeps the usual game logic and OpenXR controllers but uses a sky
background. It avoids repeated passthrough failures when the simulator's
Synthetic Environment Server is not running. Omit it for configured AR testing.
The installed runtime initially rejects `VK_KHR_portability_enumeration` and
retries successfully; confirm the scene renders rather than treating that one
startup message as an application failure.

Simulator keyboard controls:

- `[` / `]`: cycle active input devices. Check the active controller in Inputs.
- `B`: controller A/X, spawn.
- `N`: controller B/Y, recolor.
- `U`: grip. Middle mouse double click provides sticky grip.
- `M`: menu (select the left controller).
- `T` / left mouse: trigger.
- `W/A/S/D/R/F`: move active devices; arrows/Q/E rotate them.
- `Y/H/G/J`: thumbstick. Right thumbstick selects shapes; left handles undo/redo.

For an automatic visual checkpoint using the real OpenXR runtime, add
`--scene res://tests/xr_smoke.tscn` before `-- --opaque`. It uses the production
spawn/pickup/color/save/load methods to create and reload two separate bricks,
prints `XR SMOKE PASS`, and opens the menu. It deliberately does not claim to
verify native keyboard-to-OpenXR action bindings; test those manually using the
controls above. Both the normal game and smoke scene remain open for inspection.

Meta also provides input recording and replay in the simulator. A recording can
reduce repetitive manual checks, but it does not supply assertions on game
state. Keep the regression suite alongside any recordings.

No desktop or simulator check proves physical controller tracking, real-world
passthrough, comfort, or Quest performance. Finish with a short headset check.

## Native input observer

Run `res://tests/xr_input_observer.tscn` with the same official Meta runtime launch options as the smoke scene. It logs actual OpenXR pose changes and native controller button events; it invokes no gameplay actions and changes no tracking poses. Saves go to `/private/tmp/abccad-native-input-saves`. Add `--fixtures` after `--` to create two stationary bricks at initial hand poses for native proximity-grab testing. Fixture creation is setup, not a passing grab test.

Mouse scroll and trigger delivery have been observed. Automated B/M taps and sticky-grip clicks have not delivered controller events reliably. Full native spawn/grab/transfer/UI flows remain unverified. Meta VRS replay reproduced an initial movement capture, while a second short capture was inconclusive. Do not equate the method-driven smoke checkpoint with end-to-end native interaction coverage.


## Feature editing and movable labels

Run `res://tests/cad_feature_labels.tscn` with the headless regression command
above. This checks sketch/extrude ordering, editing existing depths with later
cuts, failed-edit rollback, stale numeric targets, close-circle label spacing,
click versus drag, label save/load and undo/redo, and native synthetic XR
trigger capture/release. `-- --preview` in a desktop rendering run also writes
feature-list and label-spacing PNGs under `/private/tmp`.
