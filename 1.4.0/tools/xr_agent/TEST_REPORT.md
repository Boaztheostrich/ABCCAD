# ABCCAD XR execution report — October 18, 2026

## Result

Agent observation and control work on the Apple M3 Mac against the actual
local project `/Users/boazburnett/Documents/GitHub/ABCCAD/1.4.0`.
Branch `dev`, starting commit `affac355b0778c54729bfdbd20fd01b849919aab`.
The repository already contained substantial uncommitted work; it was retained.
The `godot test/ABCCAD-review` copy was inspected but was not the implementation target.

Godot: `/Applications/Godot.app/Contents/MacOS/Godot`, 4.5.1.
Live backend: Mobile/Metal on Apple M3; renderer project settings were not changed.
Simulator: `/Applications/MetaXRSimulator.app`, 207.1.0.49.123.
Operator: Standalone 207.0.1, macOS arm64 layer and universal stdio proxy.
CLI: Meta VR CLI 1.8.0.17.10, installed in the original workspace's
`xr-workflow/tools/metavr/bin/metavr` without shell configuration changes.
Simulated device: Meta Quest 3, 72 Hz, both sources controllers; active/focused
OpenXR session. Bedroom was the selected synthetic environment, but interaction
verification used the existing opaque-background option rather than real passthrough.

## Advanced CAD MVP (subsequently authorized)

The requested advanced-mode feature is implemented. See [CAD MVP report](../../cad/CAD_MVP_REPORT.md)
and [controls guide](../../cad/README.md). It includes planar sketches, automatic
constraints, New/Add/Remove extrusion, dimension-driven regeneration, movable
origin, view-only scaling, and mixed save/load with verified millimeter exports.
The earlier sections below retain the preceding bug-fix history.

## Confirmed defects and fixes

1. Operator was absent. Installed it and registered its exact stdio proxy path
   once in Codex. The CLI distribution's nested extraction and missing proxy
   execute bit made automatic discovery unreliable; the executable was fixed
   and the launcher/registration use the actual manifest/library/proxy folder.
2. Operator selects Touch Plus. ABCCAD only declared the older Touch profile,
   causing Godot to leave trackers inactive despite successful layer-side calls.
   Added Touch Plus with the existing action bindings, preserving other profiles.
3. Homebrew Simulator v71 accepted some automation commands without delivering
   sustained/successive values to Godot. Matching experiments on current 207.1
   delivered Grip, button transitions, and poses reliably. Meta's updater did not
   recognize the Homebrew installation, so the official current standalone app
   was installed. The v71 runtime and system runtime symlink remain as rollback;
   launcher selection is per-process.
4. Both hands set a world transform before parenting spawned blocks under the
   XR origin, applying a moved origin twice. Frozen/restored blocks also inherited
   later player-origin movement while voxel records stayed fixed. Spawn after
   parenting, and use top-level world transforms for spawned/restored blocks.
   Six new position cases failed before this fix; all now pass, with additional
   rotation checks.
5. Left trigger's duplicated exporter lacked brick support and wrote an 84-byte,
   zero-triangle STL while reporting success. Existing export entry points now
   use the shared exporter.
6. Left UI trigger clicks ran both the standalone export and pointer action.
   A real left-pointer Save produced an unwanted STL. Standalone export now
   yields to active UI pointers; Save/Load no longer produce accidental exports.
7. The shared exporter treated cell centers as mesh corners, shifting solids by
   0.05 m on every axis, and rebuilt wedges/corners with independent formulas.
   All 120 shape/orientation cases failed initial alignment checks. Export now
   uses each placed object's actual world-transformed mesh exactly once. This
   also avoids exporting multi-cell panels as hundreds of overlapping cell cubes.
   Empty/unplaced geometry is not exported as a successful empty build.

Intentional differences retained: right stick changes type and left mirrors it;
left stick performs undo/redo. Right standalone trigger export was already
commented out in the base commit and remains disabled. Both menu pointers export.
No new controls, transform tools, room fallback, or anchoring feature were added.

## Additional editing defects found on the second pass

8. Simple blocks restored by undo/redo did not recover their internal cell list.
   Re-grabbing and moving one left a phantom master cell, so subsequent saves
   failed validation. Restoring the simple block now also restores that list.
   The new tests reproduced 18 failures before the fix (three assertions for
   each simple type and hand).
9. All five block scripts ignored accepted grabs during a 0.5-second cooldown.
   Rapid re-grabbing left placed cells registered while the object was held.
   Removed that logic-level cooldown: an accepted XR Tools grab always removes
   the object's footprint. All ten per-type/hand rapid-grab cases failed before
   the fix and now pass.
10. Brick/panel colliders were cube-sized, wedge used a cube collider, and corner
    used an independently defined hull. The shared collider script now derives
    a unique convex shape from the actual visible mesh's local transform. It is
    attached to all five convex block scenes. Five of six collision checks failed
    before the fix; all pass, including a physics ray at the panel's visible edge.

Live native inputs then passed 22 checks across both hands and all five types:
rapid re-grab, redo/move, and panel-edge pickup. The resulting multicolor build
contains 10 objects and 252 cells. Left-pointer save after head movement and
right-pointer reload in a fresh Godot process preserved all transforms, colors,
shapes, and occupied cells. Save: `save_2026-10-18T11-22-05_44354337.json`.
Both pointers exported the reloaded build: 5,084 bytes and 100 triangles each,
with every triangle matching the scene. Samples: `evidence/edited-left.stl`,
`evidence/edited-right.stl`; reproducible save: `evidence/edited-all-blocks.json`.

The first live panel attempt fell outside the bounded simulator floor because
of test staging. The test now spawns unheld objects over the floor, grabs them,
and then moves them to separated test positions. This was corrected in the
harness and is not counted as an application defect.

Round-two evidence: `edit-history-validation.json`, `round2-native-save.log`,
`round2-native-load.log`, `round2-export-validation.json`, and the before/after
engine logs under `evidence/`. Final engine results: 147 gameplay, 602 STL, and
6 collision checks, zero failures.

## Third-pass handoff and occupied-hand load checks

11. XR Tools emits an intermediate `dropped` signal while swapping hands. Every
    block logic treated it as a final release and tried to snap/place. When the
    held block was over an occupied cell this deleted it, even though the other
    hand had accepted it. All ten type/direction cases reproduced the deletion.
    Drop callbacks now run deferred and skip blocks that are still held or queued
    for deletion. A handoff creates no placement history and preserves neighbours.
12. A swap released the source grab but retained its pickup function's object
    reference and copied collisions. Native telemetry showed both hand pickups
    referencing one block. After release, the shared helper now reconciles source
    pickup state after the swap finishes; it only cleans the matching object when
    that pickup no longer owns it. All ten stale-state regressions now pass.

Native results: 20 successful checks cover every block type in both directions,
source cleanup, no occupied cells while held, destination recoloring, movement,
and final cell counts. The resulting build has 10 objects and 252 cells. Real
menu load with both grips occupied clears both held objects/pickup states without
late drop placements. A second load with the other pointer and a fresh-process
load preserve every transform, color, type, and occupied cell. Saved build:
`save_2026-10-18T12-01-47_46948686.json`, copied to
`evidence/handoff-all-blocks.json`.

The native harness explicitly waits for the object's actual position before
releasing it: issuing pose and grip changes back-to-back can release before a
physics frame applies the movement. This test timing issue was corrected rather
than counted as an application defect.

Both menu pointers exported the fresh-process restored build: 5,084 bytes and
100 triangles each, every triangle matching the live placed meshes. Samples:
`evidence/handoff-left.stl` and `evidence/handoff-right.stl`.

Final engine totals are 227 gameplay, 602 STL, and 6 collision checks, zero
failures. The gameplay additions include both hands holding every type during
load and subsequent repeated save/load, plus occupied-cell handoffs and cell
ownership. Evidence is under `evidence/round3-*`, `handoff-validation.json`, and
`held-load-validation.json`. The collider and existing export geometry remain
unchanged by this round. No application feature or new control was added.

## Evidence and acceptance

- PASS — local project/install inventory, live rendering baseline and versions.
  Baseline logs show v71, Mobile/Metal, focused session, both Touch profiles.
- PASS — live session/head/controller reads through Operator, including the
  registered stdio proxy; captures show the actual running app.
- PASS — independent controller pose changes reach Godot, with valid trackers.
- PASS — X/A spawn exactly once while held; Y/B increment once and change the
  actual held mesh material; analog Grip grabs, moves, releases, and clears.
- PASS — right type selection, mirrored left selection, neutral stick restoration.
- PASS — real pickup/recolor/move/rotation/undo/redo using blocks from either side,
  including objects restored from saves. Loaded held blocks are replaced without
  leaving either pickup function holding a stale object.
- PASS — snapping creates the expected voxel counts. World positions and rotations
  remain unchanged when the player origin moves or rotates.
- PASS — native save/load after head movement and turning, same-session and
  across fresh Godot processes. Transforms, shape, material color, and cell counts
  match; successful load closes the UI. Both pointers were exercised. Test saves
  were isolated in `/private/tmp/abccad-xr-agent-saves-20261018-final`.
- PASS — 227 gameplay regression checks; no failures.
- PASS — 602 STL checks; no failures. All five types at all 24 orthogonal rotations,
  negative coordinates, exact triangle/vertex/bounds checks, mixed adjacent
  assembly, one export per multi-cell object, and exclusion of an unplaced block.
- PASS — complex native build: 58 objects, 434 cells, all five types, multiple
  colors per type. Saved through the real pointer UI, then loaded after restart
  from `save_2026-10-18T11-00-03_79133100.json`, with exact transforms/colors/cells.
- PASS — left and right native STLs of the restored complex build: each 30,884
  bytes, 616 triangles, every triangle matches the live placed meshes. Bounds:
  X [-1.65, 1.65], Y [0.05, 0.85], Z [-1.55, -0.45], in existing world units.
  Samples: `evidence/complex-left.stl`, `evidence/complex-right.stl`.
- PASS — repeated app start/stop and reconnect across more than three cycles.
  Final export-code processes included PIDs 32327, 34206, and 34604; normal-main
  launcher verification used PID 35217. Fresh stdio proxy reads succeeded.
  Duplicate launch was refused, and verified `--stop` was safely repeatable.
- PASS — final source whitespace and Python syntax checks. No final-run script
  errors. Existing ViewportTexture/startup passthrough warnings were not counted
  as newly introduced defects.
- PASS — launcher/configuration, reproducible native checks, regression tests,
  reusable complex fixture, focused rollback patch, screenshots, and this report
  saved in the actual project.
- BLOCKED — a complete physical-keyboard manual button matrix cannot be established
  through the current computer-use input synthesis. Native mouse scrolling did
  reach actual head movement; synthesized B taps did not spawn. This is distinct
  from direct Operator input, which passed. Real user keyboard/controller testing
  remains a separate check; no claim of physical-device validation is made.
- BLOCKED — physical Quest same-room relocalization, changed-room compass heading,
  hardware hand tracking/performance, and actual passthrough quality were not
  tested on a headset. JSON stores app-world coordinates/bases, not anchor IDs.
  Same-room recognition requires a separately approved spatial-anchor feature;
  ordinary OpenXR coordinates alone do not guarantee a common origin across sessions.

## Files and routine

Production changes: `left_hand.gd`, `right_hand.gd`, `openxr_action_map.tres`,
`VoxelExporter.gd`, `BlockInteractions.gd`, the five block logic scripts, shared collider script, and
collider bindings in cube/brick/wedge/panel scenes. Tests: expanded `tests/regression.gd`, added the optional
`xr_agent_probe`, `stl_geometry`, `collision_geometry`, and `build_complex_fixture` scenes/scripts;
fixture files are under `tests/fixtures`. Workflow scripts/config/notes are
under `tools/xr_agent`. Original source backups and a focused reverse diff are
under ignored `tools/xr_agent/rollback`; no unrelated changes were staged.
The original workspace also retains raw baseline/operator logs and the protected
pre-registration Codex configuration backup.

Start from `1.4.0`: `python3 tools/xr_agent/launch.py`.
Check: `python3 tools/xr_agent/proxy_check.py`.
Stop: `python3 tools/xr_agent/launch.py --stop` (or Ctrl-C in its terminal).
See `README.md` for isolated tests and loading the complex pre-state.
The test Godot process was stopped cleanly after validation; no Operator server
is left listening. The simulator frontend can be reused on the next launch.

Physical-room persistence details and primary references are in the workflow
README. No scheduled automation was created. A separately requested advanced CAD MVP was
subsequently added; its controls, validation, and limits are documented above.


## 1.4.17 — angular dimensions and centered face sketches
- Native Godot captures verify inside/supplementary arcs, live two-line selection,
  degree labels, sketch UI, and a centered circular face with its projected center.
  Evidence: `cad-angle-inside.png`, `cad-angle-outside.png`,
  `cad-angle-placement.png`, `cad-angle-ui.png`, and
  `cad-centered-face-circle-center.png` under `evidence/`.
- Nine affected suites passed 331 checks: angle 38, face centers 16, projection 75,
  alignment/reuse 35, interaction 49, sketch workflow 30, geometry 35,
  persistence 12, and CAD STL export 41. No script errors in final suite logs.
- Coverage includes driving/supplementary angles, fixed lengths/anchors,
  constraint conflict rollback, undo/redo, JSON validation, solid rebuild/export,
  rotated off-center face sketches, projected-center snapping and retained anchors.
- Physical controller feel and headset legibility remain user feedback checks.


## 1.4.18 — face-attached Remove membranes
- Reproduced the reported workflow: a 10 mm plate, a central base-plane circular
  through-hole, and a second circle cut -54 mm inward from a picked solid face.
  The initial 24-case orientation/side matrix failed in 14 cases with cap triangles
  remaining across the second hole.
- Fixed shared boundary handling and stabilized face frames after previous CSG.
  The cutter's starting cap crosses a shared surface by 0.02 mm. Far-cap padding
  is limited to outer depth bounds, preserving internal blind-cut depths and
  rejecting repeated no-op cuts. Preview and commit share the same calculation.
- Final validation: 688 checks across eight suites, all passed. Face-cut matrix
  435, cut boundaries 56, extrude drag/preview 32, CAD STL 41, CAD geometry 35,
  angle dimension 38, face centers 16, alignment/reuse 35.
- Face-cut cases cover 12 orientations, both sides, moved parts, -54 mm through,
  -10 mm exact-thickness through, and -5 mm blind cuts. Five positions are ray
  checked from both sides, plus binary STL round trips, settled live preview,
  and no document mutation during preview. Strict scalar-double ray tests avoid
  float picker tolerances admitting rays outside skinny CSG triangles.
- Native Metal captures `evidence/cad-face-cut-front.png` and
  `evidence/cad-face-cut-back.png` show both holes open in ordinary solid mode.
- Existing saved mesh caches are preserved; the fix is applied to new operations
  and solid history rebuilds. Exact headset failing design remains optional
  additional evidence if the user saves `cut-check`.


## 1.4.20 — multiple shapes per sketch and selected-area extrusion
- Multiple circles/rectangles/stopped line chains share one sketch entry, eye,
  delete confirmation, and Clear constraints action. Explicit new sketches and
  pre-existing saved sketches remain independent.
- Planar half-edge arrangements find enclosed cells across intersections,
  collinear overlaps, projections, and independent chains. Nested loops become
  holes. Exact trapezoid fills keep excluded holes and concavities unfilled.
- One area selects automatically. Several areas prompt for pointer selection;
  either controller toggles orange fill/outline. Apply requires a nonempty set.
  The selected regions are used by preview and atomic New/Add/Remove operations.
- Saved feature definitions preserve region selections and source shapes.
  Stable boundary identities retain selected cells across supported driving edits,
  including moving circle intersections and changing adaptive tessellation.
- Native Metal captures under `evidence/cad-multi-*.png` verify one sketch entry,
  selection prompt, multiple orange areas, holes in the fill, depth preview,
  and a final solid containing only the selected islands/areas.
- Final affected-suite run: 1,129 checks across 20 suites, no failures or script
  errors. Includes 55 multi-sketch, 22 arrangement, 11 actual-pointer checks,
  and all earlier cut/pickup/dimension/persistence/visibility regressions.
- OrcaSlicer independently reports both generated test STLs as manifold one-part
  objects: 40×40×10 mm annulus and 80×50×10 mm plate with two through-holes.
  Validation STLs are in `builds/ABCCAD_multi_*_validation.stl`; no test cloud
  uploads were made. Cached profile queries measured 0.022 ms/query on this Mac;
  physical Quest interaction performance remains a device feedback check.
- A New operation currently returns one CAD part for all selected islands;
  disconnected islands move together. Old sketch entries are not auto-merged.


## 1.4.21 — printable topology and guarded STL export

- Reproduced F05 from the native simulator's actual 16-triangle binary STL,
  retained at `tests/fixtures/stl-regression/bowtie-nonmanifold.stl`.
- Merge adjacent selected cell boundaries in 2D before building prisms; reject
  point-only region connections. This also removes CSG internal walls from
  selected overlapping/adjacent cells while preserving holes and islands.
- Validate the resulting solid before committing New/Add/Remove or a dimension
  history rebuild. Reject non-manifold edges, disconnected vertex fans, open
  boundaries, and inconsistent winding. Accommodate CSG T junctions without
  modifying their nonzero geometry; remove exact zero-area CSG debris.
- Shared app STL save checks topology before any file write or Drive enqueue.
  Main-menu assembly export validates original parts independently, retaining
  the existing behavior of separately placed touching classic blocks.
- Old invalid saves remain loadable and unchanged for repair. Invalid exports
  give geometry-specific feedback rather than a storage-error suggestion.
- 2,382 checks across 25 suites passed, including 29 new printable-solid
  regressions, 435 selected-face cut checks, 56 boundary-cut checks, and 120
  classic shape/rotation export cases. Final Godot runs had no GDScript errors;
  known XR-disabled shutdown tracker warnings remain engine output.
- OrcaSlicer --info independently reports the annulus and two-hole plate as
  manifold one-part objects with their expected dimensions and base Z=0.
- Test execution was isolated in `/private/tmp/abccad-stl-fix`; the final run
  had no configured upload key. Personal source/configuration stays intact.
- Physical Quest testing is still required. No install or public push is part
  of this fix. Layers/dense-sketch performance is deferred by user request.
- User explicitly requested keeping the personal upload key for testing and
  a reminder before the public push; see `RELEASE_CHECKLIST.md`.


## 1.4.22 — CAD-first startup and confirmed light workaround

- Boot directly to the CAD workbench after the existing tracking startup delay.
  The old block intro never appears during CAD startup, even on first install.
- Settings now offers Legacy block mode, off by default. A saved explicit choice
  persists; the old `enabled=false` default does not opt existing users into
  legacy mode. Switching to CAD immediately reopens its panel and dismisses any
  legacy tutorial. Mode saves preserve the existing probe calibration.
- Both controller scripts suppress legacy-only spawn/color/joystick/export
  shortcuts whenever CAD mode is enabled, including with its panel closed.
  The left menu button still opens Save/Load/Export and Settings.
- Default Front and Left lights off in the scene, preserving other lights and
  both Lights-tab toggles. User confirmed on Quest that disabling these two
  eliminates the black squares. This is a default-lighting workaround; no
  unverified engine shader fix or geometry change is claimed.
- New startup suite covers fresh/old/default/persisted modes, native controller
  input, intro visibility, pointer activation, mode switching, retained geometry
  and calibration, plus light defaults/toggling/restart behavior.
- Personal Drive upload configuration remains unchanged. See the public release
  reminder in `RELEASE_CHECKLIST.md` before distributing a public package.

- Validation: 2,411 checks across 26 suites pass, including the final 29-check
  startup/light suite; no GDScript errors in passing runs.


## 1.4.23 — Front faces the viewer during Origin dragging

- Origin trigger-drags derive a horizontal heading from the headset to the
  new origin in model space. Front faces the viewer, Top stays ground-parallel,
  and Right stays perpendicular. Pitch/roll are excluded; near-vertical views
  preserve the last stable heading. Release freezes the heading.
- Actual base-plane frames drive drawing, plane picking and future extrusion;
  this is not a visual-only billboard. Existing sketch orientations and solid
  geometry keep the prior translation-only origin-move behavior.
- Optional validated `origin_yaw` persists in CAD snapshots, save/load and
  undo/redo. Old saves default to zero yaw. Heading-only empty workspaces are
  included in the CAD save envelope; typed translations retain heading.
- New origin-facing checks exercise viewer positions and head tilt, orthogonal
  level base planes, retained old geometry/sketch frames, new sketch frames,
  save/load and old-save defaults, invalid data rejection, anchored view zoom
  and rotated-plane picking, native trigger input, one checkpoint per drag,
  release stability, undo/redo, and saving an otherwise empty rotated workspace.
- Personal Drive configuration, CAD startup and Front/Left lights-off defaults
  are retained. See `RELEASE_CHECKLIST.md` before the public push.

- Validation: 2,451 checks across 27 suites pass, including 40 origin-facing
  checks and all previous STL/startup/controller regressions.
