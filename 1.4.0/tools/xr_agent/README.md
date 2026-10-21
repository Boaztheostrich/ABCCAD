# ABCCAD agent-controlled XR workflow

Tested October 18, 2026 on this Apple M3 Mac with Godot 4.5.1,
Meta XR Simulator 207.1.0.49.123, and Operator Standalone 207.0.1.
The working project is `/Users/boazburnett/Documents/GitHub/ABCCAD/1.4.0`,
branch `dev`, base commit `affac355b0778c54729bfdbd20fd01b849919aab`.
Pre-existing uncommitted changes were retained.

## Start and connect

From the `1.4.0` project directory:

```sh
python3 tools/xr_agent/launch.py
```

The launcher uses the discovered paths in `config.json`, selects the 207.1
runtime only for its Godot child, enables the Operator layer, preserves other
layer environment entries, and runs Mobile/Metal. It validates the live
application identity before reporting connection success. It refuses an
occupied Operator port or another workflow session. Ctrl-C terminates only
its owned Godot child; the simulator frontend may remain open for reuse.
For an agent-started session, `python3 tools/xr_agent/launch.py --stop` verifies
the recorded PID and command before signaling only that Godot child.
Logs are in `tools/xr_agent/evidence/`, and `session.json` records the owned PID
and current log. The default scene uses your normal saves.

The simulator's global activation toggle can say disabled because the system
runtime still points at the preserved Homebrew v71 rollback installation.
The launched process explicitly uses 207.1; inspect its startup log or live
runtime info rather than changing the global toggle.

Codex has one global `meta-xr-operator` stdio registration pointing directly
at the installed bundle's macOS proxy. An already-running agent may need a
new session to discover the new registration. The verification client works
without an agent restart:

```sh
python3 tools/xr_agent/proxy_check.py
python3 tools/xr_agent/operator_client.py openxr_get_session_info
```

The direct local client connects to the documented SSE endpoint and uses the
live tool schemas, without ADB/device forwarding. `AGENTICXR_MCP_PORT` is
honored by the launcher and diagnostic client. Keep it consistent for the
proxy too if changing it from 8720.

Meta's CLI 1.8.0.17.10 installed the Operator bundle inside a versioned
subdirectory and left its proxy non-executable. Execute permission was fixed;
using the absolute path avoids the CLI's incorrect "not installed" detection.
Do not create another registration through CLI federation. If updating the
bundle, update `config.json` and the existing registration's path.

## Existing controls

- Left X / right A: spawn once per press; left Y / right B: cycle that hand's
  color and recolor the block it holds.
- Both hands: analog Grip grabs, moves, and releases eligible blocks.
- Right stick: choose block type; left mirrors that selection. Left stick:
  undo/redo. These differences are intentional existing controls.
- Left Menu: toggle the menu at the current head position. Either pointer
  can save, select/load a file, and export through its trigger.
- Left trigger with UI pointers inactive: existing export shortcut, now routed
  to the shared exporter. With UI active, the trigger belongs to the pointer,
  so Save/Load clicks no longer also export. Right standalone trigger export
  remains disabled as in the original project.

Release buttons and center sticks between presses. Clear Grip/Trigger after
errors; use `openxr_release_input_devices` when handing control back.

## Repeatable isolated validation

```sh
ABCCAD_TEST_SAVE_DIR=/private/tmp/abccad-agent-validation \
  python3 tools/xr_agent/launch.py --probe
```

The optional probe scene runs the real main scene and only snapshots state,
except for an explicitly supplied test-save directory, which redirects both
the SaveSystem and its UI. It is not part of normal gameplay startup.

In another terminal, `python3 tools/xr_agent/validate.py` tests both hands'
poses, single spawning, native analog pickup/movement/release, actual material
colors, snapping, and block selection. It changes the test build.
`edit_history_check.py` starts in an empty probe scene and exercises every type
with both hands: rapid re-grab, undo/redo followed by movement, and panel-edge
pickup. It leaves a 10-object multicolor build suitable for save/export checks.
`handoff_check.py` separately starts empty and transfers every type in both
directions, verifying source-hand cleanup and final recolor/placement. After
saving that build with `save_check.py save`, `held_load_check.py` exercises
load with both grips occupied and a repeated load using the other pointer.
`stress_check.py` additionally moves/recolors blocks with the opposite hand,
rotates them, and uses native undo/redo. `save_check.py` exercises real menu
pointers after head movement and records/verifies world transforms, colors,
and voxel counts. `export_check.py` creates actual STLs in Downloads from
both pointers and compares every triangle with the live placed meshes.

The engine regression suites need no simulator:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --xr-mode off \
  --path . --scene res://tests/regression.tscn --quit-after 2400
/Applications/Godot.app/Contents/MacOS/Godot --headless --xr-mode off \
  --path . --scene res://tests/stl_geometry.tscn --quit-after 1000
```

Expected results: 227 gameplay checks, 602 STL geometry checks, and 6 collision
checks, no failures. Run `res://tests/collision_geometry.tscn` with the same
headless command to check collider vertices and panel-edge ray pickup.
The STL suite writes fixtures under `/private/tmp/abccad-stl-geometry` unless
`ABCCAD_STL_TEST_DIR` overrides it. It checks all five block types at all 24
orthogonal orientations, negative coordinates, a mixed adjacent assembly,
and exclusion of an unplaced object.

## Complex pre-state

`tests/fixtures/complex-all-blocks.json` is a reusable 58-object bridge test
build with 434 cells, all five block types, multiple colors per type, panels,
pillars, a brick deck, and rotated wedge/corner caps. Its `.expected.json`
records the actual transforms/colors and mesh triangles; its STL has 616
triangles. To regenerate, run `tests/build_complex_fixture.tscn` headlessly.
To test native loading, copy only `complex-all-blocks.json` into the isolated
save directory, set the validator's `evidence/native-save-baseline.json` to
the expected metadata, and run `save_check.py load --hand left` or `right`.
Do not copy the expected metadata JSON into the save browser.

## Position persistence and remaining boundaries

Existing JSON saves store absolute app-world origins, bases, colors, cell
occupancy, and per-object grouping. Spawned and restored blocks are now
independent of the player-origin transform, so player locomotion does not
move a frozen build away from its saved voxel coordinates. Same-origin
reload/undo/redo preserves position and rotation.

A new Quest session or changed play area may establish a different physical
reference frame. Numeric coordinates alone cannot recover a physical room
location or compass west. This project has no persisted anchor IDs. Real-room
relocalization needs a separately approved persistent-anchor integration and
headset validation; no anchors, room-placement fallback, or transform tools
were added. See [Meta Spatial Anchors](https://developers.meta.com/vr/documentation/native/android/openxr-spatial-anchors-overview/),
[Godot's Meta anchor integration](https://godotvr.github.io/godot_openxr_vendors/manual/meta/spatial_anchors.html),
and [OpenXR LOCAL reference space](https://registry.khronos.org/OpenXR/specs/1.1/man/html/XR_REFERENCE_SPACE_TYPE_LOCAL.html).

STL output now contains each placed object's actual world-transformed mesh,
once, preserving the existing coordinate/unit convention. It does not export
hands, room geometry, UI, or unplaced objects. Boolean union/mesh repair was
not introduced.

Native mouse movement reached the real XR head pose after releasing overrides.
Synthesized keyboard taps through computer-use did not produce spawn events;
physical-keyboard/controller behavior on this Mac and physical Quest tracking
remain separate user/device checks. Existing startup ViewportTexture warnings
and brief pre-opaque passthrough warnings were observed before the changes.
No new final-run script errors were found.

Setup references: [Meta standalone Operator](https://developers.meta.com/vr/documentation/unity/meta-xr-operator/connecting-ai-agents/)
and [Codex MCP registration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).

## Advanced CAD MVP

See [CAD controls](../../cad/README.md) and [CAD validation](../../cad/CAD_MVP_REPORT.md).
The regular launcher includes the workbench behind Settings → Advanced mode.
For isolated native validation, start an empty probe with a test save directory,
run `cad_check.py`, restart with the same directory, then run
`cad_restore_check.py`. These create and verify the sample using real controller
poses, triggers, grip inputs, and the virtual numeric keyboard. Test preferences
are isolated alongside test saves. Sample JSON/STL files are in `tests/fixtures`.

`rollback/advanced-mode.patch` captures the feature relative to the completed
bug-fix state. Reverse this feature patch before the earlier `agent-fixes.patch`;
original feature-touched production files are in `rollback/before-advanced`.
