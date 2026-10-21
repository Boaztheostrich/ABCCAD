# Advanced CAD MVP validation — October 18, 2026

Implemented in the actual ABCCAD `1.4.0` project on branch `dev`, retaining all
preexisting work. This feature was explicitly requested after the earlier bug-fix
rounds. No commits or unrelated cleanup were performed.

## Implemented

- Settings opt-in and a separate VR workbench; ordinary block controls resume
  outside the workbench.
- Ground-aligned Front/Top/Right planes and a movable, saved workspace origin.
- Lines/closed polylines, circles, center rectangles, numeric mm dimensions,
  automatic constraints, a laser/trigger numeric keyboard, and constraint hints.
- Face-attached sketches and New/Add/Remove extrusion with feature regeneration
  after sketch dimension edits. Invalid changes retain the previous solid.
- Planar boundary conversion and reversible block-to-CAD promotion for all five
  existing block types, with conversion history and overlap guards.
- Two empty-hand grip view scaling, with geometry-independent export dimensions.
- Mixed CAD/block save/load, legacy save compatibility, and millimeter STL export.

## Engine tests

| Suite | Checks | Result |
| --- | ---: | --- |
| Existing gameplay regression | 227 | Pass |
| Existing STL shapes/orientations | 602 | Pass |
| Existing collider geometry | 6 | Pass |
| CAD geometry/constraints | 35 | Pass |
| Mixed CAD persistence/STL | 12 | Pass |
| CAD face conversion/interaction/history | 49 | Pass |
| CAD pickup, hand swaps, moved persistence/STL | 39 | Pass |

CAD checks include New/Add/Remove volume, through-cut geometry, sketch dimension
regeneration, undo/redo, no-op rejection, fixed plane normals, translation-invariant
volume, midpoint following a length edit, inference cases, malformed constraints,
invalid profiles, exact mixed saves, origin-only saves, fractional millimeter STL
bounds, conversion of every block type, overlap-safe conversion undo, and closing
a polyline without collapsing its last corner.

Run the new suites with Godot 4.5.1, `--headless --xr-mode off --path . --scene
res://tests/cad_geometry.tscn --quit-after 400`; substitute `cad_persistence.tscn`
or `cad_interaction.tscn` (1200 frames for interaction). The inherited-main
headless interaction test emits existing OpenXR-not-initialized startup messages;
its script assertions pass. Native OpenXR logs contain no final script errors.

## Native XR acceptance

Meta Simulator 207.1 / Operator 207.0.1 / Godot Mobile-Metal, Apple M3:

- 10 checks through real controller poses/buttons: Settings toggle; rectangular
  sketch; laser numeric entry; 40 × 30 × 10 mm New; face-attached 5 mm radius
  Remove; 8 × 6 × 5 mm Add; edit cut radius to 6 mm with downstream rebuild;
  verify open centerline; export; empty-grip zoom without geometry edits; origin
  movement and base planes; save. Some entries combine related assertions.
- 4 fresh-process checks: exact document restoration; full STL geometry and
  topology; laser Auto toggle; unchanged document at 4× view magnification.
- 2 mode-exit checks: disabling advanced mode hides the entry, and normal
  right-hand block spawning resumes. Test preferences were restored to off.
- Restored STL: **416 triangles, 20,884 bytes, 40 × 30 × 15 mm**. Bounds are
  X [80,120], Y [1135,1165], Z [-650,-635], in millimeters. Every exported vertex
  matches the saved solid within 0.001 mm. Normals are finite/unit length, all
  undirected edges are paired, and Euler characteristic is zero, confirming the
  expected single through-hole. CAD geometry is unchanged by magnified viewing.

Evidence: `tools/xr_agent/evidence/cad-native-validation.json`,
`cad-restore-validation.json`, `cad-mvp-overview.png`, `cad-mvp-mm.stl`, and copied
suite/native logs. Reusable fixtures are under `tests/fixtures/cad-mvp*`.
Native scripts are `tools/xr_agent/cad_check.py` (empty scene) and
`cad_restore_check.py` (fresh empty process after saving the baseline).

## Defects caught during implementation

- Baked CSG root transforms must be applied before caching the resulting vertices;
  otherwise a New extrusion could occupy the opposite side of its sketch plane.
- Controller injection must convert world targets through the current XR origin
  and world scale after zoom; the harness now does so and waits for panel settling.
- Closing a polyline onto its first point must not attach the closure inference
  to the preceding corner after discarding the duplicate endpoint.
- Face sketch planes retain source-plane coordinates in mm rather than rounding
  through meter-space tracking coordinates; base-plane origins project the saved
  workspace origin onto the selected face.
- Godot's triangle-mesh cache snaps to 0.0001 mesh units. An intermediate meter
  mesh introduced up to 0.0487 mm error in exported curved vertices. Advanced
  exports now build in final mm coordinates, with no intermediate meter cache.
- Block promotion must clear stale classic history and protect conversion undo
  against a newly occupied footprint.
- Body/sketch selection uses VR buttons rather than native desktop popup menus;
  the tool panel stays readable over geometry, and solid faces use flat normals.

## Scope and provenance

This is a mesh-based CAD MVP with a directional constraint dependency solver,
not full Onshape/FreeCAD feature or nonlinear-solver coverage. The supported rules
and limitations are in [README.md](README.md). No FreeCAD code is copied or bundled;
its C++ Sketcher/PlaneGCS source was inspected as a reference. The implementation
uses the project's existing Godot CSG engine and STL writer, with no new native
runtime dependency. Physical Quest behavior/performance and room anchoring have
not been validated or added.

Primary references consulted:

- [FreeCAD PlaneGCS source](https://github.com/FreeCAD/FreeCAD/blob/main/src/Mod/Sketcher/App/planegcs/GCS.cpp)
- [FreeCAD Sketcher inference code](https://github.com/FreeCAD/FreeCAD/blob/main/src/Mod/Sketcher/Gui/DrawSketchHandler.cpp)
- [FreeCAD licensing](https://www.freecad.org/contributing.php?lang=eng)
- [Godot 4.5 CSG polygons](https://docs.godotengine.org/en/4.5/classes/class_csgpolygon3d.html)
- [Godot 4.5 CSG baking](https://docs.godotengine.org/en/4.5/classes/class_csgshape3d.html)
- [Godot XR world scale](https://docs.godotengine.org/en/4.5/classes/class_xrserver.html)
- [Godot triangle-mesh welding source](https://github.com/godotengine/godot/blob/master/core/math/triangle_mesh.cpp)

## UI and CAD pickup follow-up

The workbench now uses a light Part Studio layout, a persistent command bar,
explicit parts/sketches list, and context panels for Sketch, Extrude, and Origin.
The numeric keypad remains usable with either hand laser and trigger.

Extruded and promoted CAD parts support grip pickup, rotation, either-direction
hand transfer, frozen release, placement undo/redo, saved poses, and sketch/feature
regeneration after movement. CAD parts stay outside the voxel grid. Saving or
loading while holding a CAD part gives an explicit release-first message.

All 970 pre-table engine checks pass. The updated native `cad_check.py` passes its 10 CAD
workflow checks. Native `cad_grab_check.py` verifies actual controller grip input,
right-to-left transfer, movement/rotation and saving. A fresh simulator process
restores that moved body and its rotated sketch planes; `cad_grab_restore_check.py`
verifies every STL vertex against the restored model within 0.001 mm.

These checks also exposed and fixed cancellation in room-scale volume sums and
ray-selection misses on tiny CAD triangles. Volume uses a local reference point;
face intersections operate in millimeter coordinates. Actual XR captures are in
`tools/xr_agent/evidence/cad-ui-part-studio.png` and `cad-ui-extrude.png`.

## Table planes and layer preview — follow-up

- Three actual controller-tip contacts define a measured reference plane, with
  contact spacing/collinearity checks, editable local tip offsets and capture undo.
- A tracking-space plane lock is independent of model view magnification. Table
  sketches, physical-size reset, rotation locking, scaled pickup, placement
  undo/redo, saved reference data and plane-only saves are covered.
- Reference exports transform every CAD body and classic block into the same
  table-local print frame. Table normal is export Z. Preview geometry and view
  magnification never enter the exported mesh.
- The layer renderer computes mid-height triangle sections for 0.2 mm slabs,
  retains holes/islands using even/odd scanline cap filling, removes hidden
  inter-layer faces, and draws true treads
  and vertical risers. It yields during work, reports circular progress, cancels
  on selection/geometry changes and retains the original solid for edits/export.
- CAD Load now opens the existing saved-build list directly.

`tests/cad_table_preview.tscn`: **50 checks, zero failures**. Together with the
970 existing checks: **1020 engine checks pass**. The new coverage includes a
25.4 × 50.8 × 76.2 mm reference block, table-frame export axes, preserving physical
size after legacy tracking zoom, scaled collision hulls, rotation lock, moved
save/load, plane-only saves, plane/placement history, true stepped ramp faces and closed volume,
open through-hole geometry and cap area, preview cancellation and loader viewport bounds.

Native XR `cad_table_check.py`: **6 acceptance checks pass** using actual hand
poses, triggers and grip inputs. `cad_table_restore_check.py`: **4 checks pass**
for fresh-process physical-size restore, lock controls, a larger curved preview
and toggling back to the exact solid. A larger preview generated **40536 vertices**.
The loader placement was corrected after inspecting actual compositor captures.

Artifacts: `cad-table-controls.png`, `cad-table-inspector.png`,
`cad-print-stepped.png`, `cad-print-smooth.png`, `cad-print-loading.png`, and
`cad-table-{native,restore}-validation.json` under `tools/xr_agent/evidence/`.
`tests/fixtures/cad-table-sample.json` is a native-created saved table reference,
1–2–3 block and curved part. Probe-tip fit and Quest room relocalization still
need hardware verification; saved stage coordinates are not spatial anchors.

References: [Godot XRServer](https://docs.godotengine.org/en/4.5/classes/class_xrserver.html)
and [XROrigin3D](https://docs.godotengine.org/en/4.5/classes/class_xrorigin3d.html).

## Quest feedback fixes — 1.4.8-cad-test

Hardware feedback exposed invisible menu lasers and CAD pickup failure at
8.43x XR world scale. The CAD grab driver now uses orthonormal controller
poses, preserving precise grab offsets and keeping the body root rigid.
The menu lasers render over the studio, remain visible on either hand, and
use hand-local lengths for collision endpoints. UI-ray tests no longer
incorrectly apply the model view transform. Scaled suppression no longer
prevents menu targeting.

Added independent laser/trigger window move and resize controls: a lower
pill and lower-right corner handle, anchored in tracking space. Geometry
and planes stay unchanged.

Verification: 1095 checks pass across the nine engine suites. CAD pickup
now has 87 checks including actual near/ranged grab-driver physics from
both hands at 0.2x, 1x and 8.43x. Readiness has 27 checks including window
movement, resize, model-view independence, and both laser endpoints.
The signed update was installed successfully on the connected Quest 3.
Physical retesting of these changes remains with the user.

## Headset feedback: sketches, visibility, face selection — 1.4.9/1.4.10

1.4.9 was installed on Quest during feedback. It adds plane selection, line
chains with a live endpoint/length preview, B to end without committing the
preview, selectable on-sketch dimensions, diameter entry, persistent driving
dimensions, and rank-based blue/black constraint feedback. The numeric solver
works per profile in dependency order; external underconstrained references
are conservatively left blue. Full freedom analysis is bounded to 128 points.
The UI has vector eye buttons for individual planes and sketches, separate
plane label positions, and thicker sketch strokes.

1.4.10 adds orange connected planar face highlighting, deselection on empty
space, consumed-sketch hiding, and viewer-facing orientation while dragging
the Part Studio pill. Releasing holds the resulting tracking-space pose.
Visibility is presentation state and does not alter export geometry.

The reported Remove first-layer artifact did not reproduce: user retried and
asked to leave it. Boolean geometry is unchanged. 28 cut-boundary checks cover
forward/reverse coplanar through cuts, rotated/translated solids, absence of
caps in export geometry, exact ring volumes, and blind-cut depth preservation.
14 selection/visibility checks include highlighting an annulus without filling
its hole. 30 sketch workflow checks cover partial/full constraints, persistent
dimensions, conflicting-dimension rollback, JSON restore and exact extrusion.
Native screenshots are under tools/xr_agent/evidence/cad-sketch-*.png,
cad-face-selected.png, and cad-studio-eye-controls.png.

Final 1.4.10 validation: **1169 checks pass** across 12 suites, including
29 readiness checks for viewer-facing dragging and fixed released orientation.
Signed artifact: `builds/ABCCAD-Quest-CAD-1.4.10.apk`, package
`com.example.voxeltestv14`, versionCode 12. Prepared for an in-place update.

## 1.4.11 feedback round

Added a signed-depth extrusion arrow with trigger-to-reverse and a panel
Reverse direction button. Boundary-only outward Removes now reject before
CSG; a Remove must decrease solid volume before it can commit. The exact
reported stray fragment has not reproduced locally; the new disc/boss cases
cover both sketch normal directions and switching from +30 to -30 after a
rejected attempt. No geometry repair of existing saved fragments is claimed.

Sketch plane alpha is 0.5. Physical snap distance grows from 3 to 30 mm;
angular inference is eligible up to 30 degrees but must satisfy the spatial
capture distance, choosing the closest equal/parallel/perpendicular/tangent
inference. Self-endpoint and immediately previous midpoint traps are excluded.
Laser endpoints use visible planes or exact mesh triangles, preserving actual
holes rather than stopping at the convex pickup hull. Trigger placement and
laser rendering now use the same ray transform. Menu targeting stays prioritary.

Confirmed sketch deletion and Clear all support Undo/Redo. Dependent parts
and sketches are explicitly listed by count in the confirmation. Deletion
intent for converted blocks is retained through save/restore and history so
redoing deletion cannot resurrect a classic block. Clear all is CAD-only.

1233 checks pass across 14 engine suites (including 56 cut-boundary, 19
direction/surface and 17 deletion checks), plus native visual inspection of
arrow directions and confirmation dialogs. Screenshots: cad-extrude-direction-
positive.png, cad-extrude-direction-negative.png, cad-delete-confirmation.png
and cad-clear-confirmation.png under tools/xr_agent/evidence/.


## 1.4.12 sketch contrast and extrusion dragging

Reproduced dimension text fading under the translucent sketch plane from an
oblique left/right view. Sketch labels now draw unshaded after the plane and
outline; blue/black constraint ink remains readable. Native angled captures
verify the result. Arrow labels use the same explicit ordering.

Either controller can trigger-drag an extrusion arrow. Release retains the
preview depth, B cancels the drag, and Apply commits. The axis calculation
converts view-space movement back to CAD millimeters, handles both depth signs,
and falls back to physical push/pull when the ray is parallel to the axis.
The Reverse direction button remains available.

A disposable prism updates immediately while dragging. New previews are exact
extrusion volumes. Add/Remove preview booleans update after 120 ms without a
depth change, with one job in flight and stale results discarded. Preview work
never edits saved/exported geometry or undo history. Original body meshes are
restored on depth changes, cancellation, command changes, and closing the panel.
Complex targets above 4096 triangles retain the translucent tool-volume preview;
preview booleans stop rebuilding after a measured build over 100 ms (including
two awaited renderer frames). These safeguards reduce headset work but are not
a substitute for profiling on the Quest.

921 checks pass across nine affected suites, including 32 new drag/preview/text
checks and 602 STL checks over 120 shape/rotation cases. The simple Remove
preview took approximately 5–7 ms in headless desktop tests including two frames;
this is not a Quest timing measurement. Native rendering confirms the cut hole
and text at oblique views.


## 1.4.14 coplanar rendering, alignment, and line reuse

The translucent plane is biased 0.7 physical mm away from the viewer, and orange
face highlights toward the viewer, exclusively for rendering. This removes
coplanar depth conflict from both directions without modifying CAD planes,
STL geometry, or laser hit calculations. Sketch line/fill annotations have
explicit overlay ordering. Native angled captures of visible coplanar plane,
solid, and face highlight show clean surfaces without the checkerboard pattern.

New face-sketch axes derive from the part's original feature frame after rigid
placement, rather than world-up. Exact coplanarity is preserved and the default
Top plane stays ground parallel. Existing saved sketch orientations are retained.

Horizontal/vertical alignment to earlier points can combine with the new
segment's own horizontal/vertical relation; a dashed guide shows the reference.
Constraints are integrated with the directional solver, numeric residuals, degree
of freedom analysis, reference validation, and saved JSON. Resume lines continues
an open chain; From vertex creates a linked new chain while preserving its
source profile; Use object edge projects one face boundary edge onto the active
plane and resumes drawing. Shared triangulation diagonals are excluded. Copied
object edges do not regenerate associatively when source face dimensions change.

1067 checks pass across 14 affected suites, including 35 new alignment/reuse
checks and 602 STL checks. A dimensioned aligned sketch extrudes and exports with
61.4 × 60.6 × 12 mm bounds. The final highlight change was followed by rerunning
the selection/visibility suite and the alignment/reuse suite. No new hardware
interaction performance claim is made; headset feedback remains the final check.
Drive upload configuration and its redirect fix from the other thread remain
intact. No commit or remote git push was performed.


## 1.4.15 persistent Project tool

The user clarified that projection must select independent object-face edges
within the current sketch and stay active between triggers. The Project tool
now does that, with gold hover, snapped laser endpoints, both-controller input,
duplicate suppression, and B/Finish Project. Coplanar face boundaries are cached;
simple faces update hover every frame, while complex sets are rate-limited.

Optional projected_edges and closed_by_projection fields serialize reference
segments independently from the drawn point chain. The projected_point
constraint references an endpoint or midpoint of an immutable copied segment;
solver, numeric residuals/rank analysis, validation, and deletion dependencies
support these references. Read-only segment references do not introduce point
solver cycles. Undo removes one projection per step.

CADProjectedGeometry assembles a simple projected loop, or closes a drawn chain
through the projected edge graph. Splitting reference edges at the drawn chain's
endpoints permits a closure beginning at a projected midpoint. Full Onshape
multi-region/nested-hole selection is outside this change. Projected edges remain
geometry copies, without automatic regeneration from later source-face edits.

1111 checks pass across 15 affected suites, including 44 Project checks and
602 STL geometry checks. Tests cover four square edges selected in arbitrary
order, duplicate/undo/redo, JSON reload, projected-only and mixed drawn/projected
extrusions, exact 40 × 40 × 7 mm export bounds, midpoint/endpoint constraints,
outside-face capture, both-side rays through zoom, actual trigger-driven profile
closure, and invalid projected-edge data. Native captures show edge hover, two
independent projected lines, the complete square region, and persistent tool UI.

The APK is prepared for later installation. The user explicitly said they will
reconnect the Quest later; no install or session restart was attempted this round.
The Drive upload setup remains preserved.


## 1.4.16 supplied cube STL regression

The supplied ABCCAD 684-byte STL has 12 triangles, eight vertices, paired edges,
and approximately 100 mm side lengths / 1,000,000 mm3 volume. However its right-
hand-rule signed volume is negative and every stored facet normal opposes its
vertex winding. The supplied Onshape cube has positive signed volume and normal
agreement. The ABCCAD file also contains arbitrary room rotation/offset; the
Onshape reference has XY bounds -50..50 mm and Z bounds 0..100 mm.

STLIO's exporter now swaps the last two Godot triangle vertices and computes
explicit cross-product normals in STL order. This fixes backface-culling and
inside/outside interpretation without changing triangle positions. CAD exports
now remove placement through the first feature sketch frame (or explicit table
frame), center XY, and put minimum Z at zero. Combined exports apply one shared
rigid transform/translation to preserve all relative assembly geometry. Raw
model/export geometry builders remain available for exact in-app comparison.

Added supplied-file fixtures and 41 CAD/STL regression checks covering all three
base planes, positive/negative extrusion, room placement rotations, serialization
round trips, through-hole normals and cap absence, and actual combined CAD/block
export alignment. The 120 block/rotation cases now also verify normal agreement,
positive signed volume, and two opposite directed uses of every surface edge;
that suite grew from 602 to 962 checks. 1200 checks pass across seven affected
suites. The earlier geometric bounds tests alone did not detect the winding bug.

OrcaSlicer 2.3.2 --info independently reports the repaired user cube as one
manifold part, base Z=0, dimensions 100.000145 × 100.000107 × 100.000214 mm
(the small residual is in the original float-coordinate geometry). The new
Godot-generated Top-plane cube imports as one manifold 100 × 100 × 100 mm part
with XY -50..50 and Z 0..100. The mixed CAD/legacy assembly imports as manifold
with two separate parts. Local logs: /private/tmp/abccad-orca-fixed.log and
/private/tmp/abccad-orca-generated.log. No cloud upload was used for these tests.

Repaired attachment: builds/ABCCAD_cube_100mm_fixed.stl. A winding-only copy is
also retained to isolate the two changes. Quick Look was attempted, but its
renderer stayed on a gray loading view on this machine; no successful native
Quick Look visual result is claimed. The STL and slicer checks above passed.


## 1.4.19 — in-app lighting isolation

Added a Lights tab at the far right of the existing Part Studio command bar.
It exposes six independent On/Off buttons for the five fixed OmniLight3D nodes
and the main DirectionalLight3D. Front (OmniLight3D5) and Left (OmniLight3D4)
are labeled “(suspected)” to support the user's Quest 3 black-square diagnosis.
Changes apply immediately and survive tab switches; app restart restores the
scene defaults. No lighting state is stored in CAD geometry, saves, or undo.

Native Godot Mobile/Metal checks exercised all six UI button bindings, verified
that each changes only its own scene light, checked state across tab switches,
restored the starting light states, and verified an unchanged CAD snapshot.
The rendered 1120 × 900 panel fits the new toolbar tab and all light rows above
the footer. Evidence is in the godot test workspace's investigations directory:
abccad-lights-panel.png and abccad-lights-check.log.

APK: builds/ABCCAD-Quest-CAD-1.4.19.apk, version code 21. Export succeeded after
removing a Finder .DS_Store file that interrupted Gradle's generated-build clean.
The app's existing certificate is used by tools/quest/sign_test_apk.py.
The actual black-square cause remains unconfirmed until the user toggles the
suspected lights on the affected Quest 3. No headset installation was attempted.
