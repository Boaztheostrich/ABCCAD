# Advanced CAD MVP

The app opens directly into the CAD workbench after headset initialization.
The block welcome screen is skipped in CAD mode. Press the left controller's
menu button for Save, Load, Export, and **Settings → Legacy block mode**.
Legacy mode is optional and its selection is remembered for the next launch;
turn it off to return directly to CAD. Closing the CAD panel does not enable
block spawning—choose Legacy block mode explicitly for block controls.

## First part

1. Open **Sketch**, then select **Front**, **Top**, or **Right** in space or in the panel. Top stays parallel
   to the ground; head tilt never tilts the base planes.
2. Choose **Center rectangle**, **Circle**, or **Line**. Aim either hand's laser
   at the plane and pull trigger. A rectangle takes a center and corner; a circle
   takes a center and radius point. Lines chain endpoints. Close a line profile
   by clicking its starting point or using **Close profile**. Choose another tool
   or end/restart Line with B to add another shape or chain to this same sketch.
   Use **New sketch** or choose a new plane when you want a separate sketch.
3. Press a dimension button. Use the floating numeric keyboard with the hand
   lasers and trigger, then **Apply**. Width/height are full rectangle sizes;
   circle size is diameter. Select any on-sketch segment dimension to edit that edge.
   Entered dimensions persist as driving constraints. Blue means underdefined;
   black means the geometry is fully constrained. B ends the current chain
   without committing its preview endpoint.
4. Open **Extrude**. One enclosed area is selected automatically. When there are
   several, point and trigger inside each area you want; selected areas turn orange.
   Trigger again to deselect. Enter **Depth** and choose **New**, **Add**, or
   **Remove**, then **Apply extrude** to apply that depth to all selected areas.
   Positive depth follows the sketch normal; negative depth reverses direction.
   For a cut into a selected outside face, use a negative depth.
5. **Select**, aim at a solid, pull trigger, then **Sketch on selected face** to add
   another sketch. Select the intended part in the left feature list if necessary.
   Add unions the profile with that body; Remove subtracts it. New creates an
   independent part. The left feature list selects parts and sketches directly with trigger clicks;
   they do not depend on desktop popup menus.
6. Select an existing sketch in the feature list, then open **Sketch**. Editing its dimensions rebuilds
   its solid features and downstream Add/Remove operations. If an edit conflicts
   with a retained constraint or cannot make a valid solid, the last good model
   stays intact. **Undo/Redo** restores CAD edits, including geometry caches.

## Moving extruded parts

Grip a CAD part with either hand to move or rotate it. Grip it with the other
hand to transfer it, then release to leave it fixed in place. This works with
the workbench open or closed. Attached sketches, cached geometry, and extrusion
planes follow the solid. The workspace's base Top plane stays ground-parallel.
Undo/Redo includes placement, and Save/Load preserves the new pose. Release all
CAD parts before saving, loading, or editing dimensions. View scaling does not
change exported dimensions. The pickup hull is convex for interaction; holes and
concave details remain exact in the visible mesh and STL.

## Table / real-object reference plane

1. Open **Table → Probe calibration**. Adjust X/Y/Z (mm from the tracked
   controller pose) so the blue marker coincides with the physical controller
   point you will touch to the surface. The default forward offset is a starting
   point, not a device-specific measured tip. This calibration is saved locally.
2. Choose **Capture table · 3 contacts**. Touch the blue probe to three widely
   spaced spots and trigger at each one. Use either hand; use the same calibrated
   controller contact point. Contacts closer than 20 mm or almost in a straight
   line are rejected. The first contact sets the origin; the second defines X.
   The third fixes the measured plane, including a real surface's tilt.
3. **Plane lock: on** anchors that plane in tracking space. **Sketch on table**
   creates a sketch on it. The original Top plane remains ground-parallel.
4. Two empty grips magnify the CAD rendering around the table origin. The table
   grid stays fixed. Typed dimensions and exported geometry do not change.
   **1:1** returns to physical size: a 25.4 × 50.8 × 76.2 mm part corresponds to
   a 1–2–3 inch reference block. **Rotation: locked** lets a grabbed part translate
   while retaining its orientation. It does not lock its position.
5. Save stores the table pose and lock states with the model; loading starts at
   physical 1:1 in a fresh process. These are saved tracking coordinates, not a
   persistent Quest spatial anchor. Recapture after changing rooms, Guardian,
   or tracking origin, and verify contact-tip alignment on the actual headset.

When a reference plane is present, both selected-part and combined exports use
its local coordinate system: table X/Y are the print bed and the table normal is
**STL Z**. All bodies and classic blocks receive the same rigid transform, so
relative positions and sizes remain unchanged. This also makes export orientation
match the layer preview. Without a reference plane, export keeps the existing
world-coordinate convention. STL remains unitless; import it as millimeters.

## Printed-layer preview

**Layers** toggles a preview of the selected CAD part in **0.2 mm layers**. It
builds stepped cross-section geometry, including horizontal treads on slopes,
with a circular progress indicator. It runs incrementally and can be cancelled
by toggling Layers off. It regenerates after edits; grabbing temporarily shows
normal CAD geometry and regenerates on release. Other parts stay in their usual
view. The exact CAD mesh is retained and is always the source for STL exports.

With a table reference, slicing follows the table normal / exported Z. Otherwise
it follows existing STL world Z. This is a layer-shape preview without supports,
not a toolpath, bead, infill, extrusion-width, bridging, or material simulation.
It supports up to 500 mm height at 0.2 mm and caps generated geometry to keep the
MVP bounded. Thin features below a layer height are approximated by mid-layer
cross-sections; the final slab ends at the original part's maximum height.

## Automatic constraints

Inference is on by default. The cursor and tool-panel hint show the candidate
before placement. Supported relationships are origin/endpoint coincidence,
line midpoint, horizontal/vertical, parallel/perpendicular, equal line length,
circle-center coincidence (including concentric centers), and line-to-circle
endpoint tangency. Connected polyline endpoints, centered rectangles, and
rectangle orthogonality are also preserved by their construction.

Retained constraints follow their referenced geometry when dimensions change.
The dependency solver rejects cyclic references; it is not a general nonlinear
constraint solver. **Auto: off** disables inference for new points without
removing existing relationships. **Clear constraints** removes the active
sketch's retained inferred relationships so a conflicting dimension can change.
Cross-plane constraints, arbitrary compound constraint combinations, manual
constraint selection, arbitrary edge dimension selection, and arc/spline tools
are outside this MVP.

## Existing blocks

Use **Select** on a placed block, then **Convert face edges** to turn one
planar boundary into a closed line sketch. Triangle diagonals are excluded.
This works with cubes, bricks, wedges, panels, and corner pieces.

**Block → CAD** replaces the selected block with a CAD solid that accepts
Add/Remove features. It retains the visible geometry and position. Conversion
is undone/redone with the CAD buttons. It clears the old block undo/redo stacks
so they cannot respawn a duplicate of the converted part. Undo refuses to restore
an original block over a block placed there since conversion.

The legacy **Convert face edges** shortcut accepts one simple planar boundary.
For faces with several loops, use **Project** to select their individual edges
or circular rims into the same sketch, then select the enclosed areas in Extrude.

## Origin and view

**Move origin** lets you hold the right trigger away from the panel and move
its position with the controller. The X/Y/Z buttons also accept precise origin
coordinates in millimeters. Moving the origin translates the CAD workspace,
its sketches, and its solids; it does not resize them. During an Origin trigger-drag, Front turns horizontally toward the viewer,
Right stays perpendicular to Front, and Top stays parallel to the ground.
Releasing keeps that heading. Existing sketch frames keep their orientation;
new base-plane sketches use the new heading. Typed coordinates retain it. The moved origin saves even before creating a sketch.

With neither hand holding an object, hold both grips and spread your hands to
magnify; bring them together to shrink. Scaling is centered on the CAD origin
and affects the view/tracking scale, not model vertices or exported dimensions.
**View 1:1** restores real-size viewing. The tool panel resummons into a readable
position after the gesture.

## Save and STL

**Save** stores CAD solids, feature definitions, attached sketches,
constraints, origin, and any remaining blocks through the existing save workflow.
**Load** opens the existing file browser. New CAD documents use a versioned
JSON envelope; previous block-only JSON saves still load. Invalid data is checked
before replacing either part of the current build.

**Export · mm** writes the selected CAD body. The main menu's **Export STL ·
mm** includes all placed blocks and CAD bodies. With advanced mode or CAD solids
present, coordinates are exported in millimeters: a 40 mm part measures 40 in an
STL reader configured for millimeters. STL has no embedded units. Classic mode
with no CAD solids retains the previous export convention.

The exporter builds directly in final units. It avoids a meter-space triangle
cache that would round curved vertices to 0.1 mm. View scale never enters export.
Circles use faceted meshes, targeting 0.01 mm chord deviation with 96–2048 segments;
this is a mesh modeler, not a B-rep precision CAD kernel. Feature regeneration
retains sketch planes but does not provide automatic face-topology reattachment
when a previous edit moves a supporting face. Reselect the new face when needed.

## Verification and sample

See [CAD_MVP_REPORT.md](CAD_MVP_REPORT.md) for automated and native XR results.
`tests/fixtures/cad-mvp.json` is the saved 40 × 30 mm plate with a 12 mm diameter
through-hole and an 8 × 6 × 5 mm added boss. Total depth is 15 mm. Its origin was
moved 100 mm in X. `tests/fixtures/cad-mvp-mm.stl` is the verified final export.

To inspect the sample through the existing load menu, copy its JSON into the
app's save directory or the launcher's explicitly isolated test-save directory.
Keep the `.stl` out of the JSON browser. Launch instructions are in
`tools/xr_agent/README.md`.

Physical Quest controller ergonomics, passthrough, and performance still need
headset testing. This feature adds no persistent room anchors; physical room
relocalization remains a separate integration.

## Part Studio window controls

Aim either controller laser at the blue pill below the window, hold trigger,
and move the controller to reposition the window. While dragging it turns
toward your eyes; releasing keeps that pose. Trigger-drag the blue
lower-right handle to resize it. The window retains its tracking-space
position and physical size during model-view zoom and recentering. These
controls never alter sketches, reference planes, or exported dimensions.
Two empty grips continue to zoom the model view. Both menu lasers remain
visible and show a small hit cursor.

## Visibility and selection

Eye buttons beside planes and sketches show or hide their drawing without
changing geometry or STL output. A completed extrusion hides its consumed
sketch and sketch plane; use its eye to show it again. Selecting a face
highlights its actual connected triangles in orange, retaining holes. Click
empty space to clear the face selection.

## Extrusion direction, snapping and reset

Extrude displays a 3D arrow and signed depth. Trigger the arrow, or select
**Reverse direction**, to flip the sign before Apply. A Remove that only
touches the body's boundary is rejected before the boolean runs. Sketch
planes use 50% opacity. Snapping has a 30 mm physical capture distance
(10x the earlier 3 mm), converted through view zoom so it stays consistent.
The laser terminates on visible planes and exact object triangles; real holes
remain open to the ray. Drawing input follows that same laser ray.

Trash buttons sit beside sketch eyes. Deleting a sketch that defines a part
also deletes that dependent part and its attached/dependent sketches; the
confirmation reports those dependencies. **Clear all** is at the bottom of
the sketch list and confirms clearing all CAD parts and sketches. Saved
files, classic blocks, table reference/calibration and base planes remain.
Both actions support Undo/Redo and reject deletion while a CAD part is held.


### Extrusion arrow preview (1.4.12)
Trigger-drag the arrow with either controller to adjust signed depth. Release
keeps the preview; B during dragging restores the starting depth. Use Reverse
direction for a quick sign flip, typed depth for precision, and Apply to commit.
The translucent extrusion volume follows immediately. Add/Remove shows the
boolean result after a short pause for moderate parts; complex/slow parts keep
the volume preview to limit headset work. Previewing does not change exports.


### Alignment and edge reuse (1.4.14)
Line endpoints can align vertically or horizontally with earlier sketch points,
while retaining a horizontal/vertical constraint to their preceding endpoint.
A dashed gold guide shows the alignment and the relationship survives dimensions
and save/load. Coincident/end-point snaps still take priority.

In Sketch, Resume lines continues the selected open chain after B. From vertex
starts a new chain linked to a selected vertex without opening or destroying the
original closed profile. Use object edge copies a face boundary edge onto the
current sketch plane, then continues drawing from the nearer endpoint. An empty
sketch is reused; further shapes and stopped chains remain in the same sketch.
Perpendicular edges with zero projected length are ignored. These are geometry
copies, not associative references to future changes in the source face.

New face sketches inherit their part's frame after placement rotation, keeping
their axes aligned with the part. Existing sketches preserve their saved planes;
the default Top plane remains parallel to the ground.


### Project tool (1.4.15 clarification)
In Sketch, choose Project. A square face has four selectable boundary lines;
triangulation diagonals are excluded. Aim near a line with either laser, see the
gold highlight and snapped cursor, then trigger to copy it into this same sketch.
Project stays active for further selections; duplicates are ignored. B / Finish
Project ends selection. Each copied edge can be undone individually.

Projected edges are stored separately from drawn line chains in the sketch.
Line starts/endpoints can snap to their endpoints and midpoints. Drawn chains
can close using projected edges, including a partial edge from its midpoint. A
simple closed loop made entirely of projected edges can also be extruded.
As of 1.4.20, enclosed regions from these edges can be selected together with
other sketch shapes, including nested holes. Copies remain fixed sketch
references, not associative links to later source-face dimension changes.

This supersedes 1.4.14's single-edge-copy-and-continue behavior.


### Slicer-ready STL export (1.4.16)
The STL writer converts Godot clockwise faces to outward counterclockwise STL
triangles and writes normals that agree with that order. Selected CAD exports
use their first feature's sketch frame, removing room-placement rotation and
translation; a captured table/print plane takes priority. Exports are centered
in XY with their lowest Z at zero, retaining millimeter dimensions.

Combined CAD/block exports use one common rigid frame and bed translation for
the entire assembly, retaining relative positions and rotations between parts.
On-device geometry, sketch placement, and saved designs are unchanged by export.


### Angular dimensions and face sketch references (1.4.17)
In a line sketch, choose **Angle dimension**, trigger two segments sharing an
endpoint, then trigger to place the arc. The preview starts with the inside
angle; placing outside either line selects the supplementary angle. B cancels.
Select the degree label to enter a driving angle (between 0.01° and 179.99°).
Existing lengths and constraints are retained, conflicting edits roll back,
and edits to extruded sketches rebuild their solid history. Placement and
angles survive save/load and undo/redo. Currently the two lines must belong to
the same connected line chain and share an actual vertex; projected reference edges
are fixed copies, not editable angular segments.

New sketches on solid faces use the face bounds center instead of the workspace
origin projected onto that face. Their axes still follow the part orientation.
Projecting a circular rim adds a center cross and a fixed, snappable center
reference for new sketch geometry. The center is saved and undone together
with the rim. Re-project an older rim to add a missing center reference.


### Selected-face Remove boundary fix (1.4.18)
Remove cutters cross a coincident starting face by 0.02 mm so a rotated,
previously triangulated cap cannot survive as a membrane. An exact through-cut
end is extended only at the body's outer depth bounds; internal blind floors
keep the entered depth. Boundary-only outward cuts remain rejected. The settled
boolean preview and committed feature use the same limits; saved sketch planes
and depth values are unchanged.

Face sketch normals use the largest coplanar source triangle rather than the
small triangle under the pointer, stabilizing face frames after earlier cuts.
This applies to new cuts and subsequent solid rebuilds; cached geometry in old
saved designs is not silently rewritten on load.


### Multi-shape sketches and selectable areas (1.4.20)
A sketch now contains multiple circles, rectangles, and independently stopped
line chains under one feature-list entry. Its eye, trash action, and Clear
constraints apply to the whole sketch. Existing saved sketches retain their
separate entries; they are not silently merged. Explicit New sketch and a new
plane still create separate sketches.

Extrude finds the enclosed cells formed by all sketch geometry, including
intersections, nested circles, projected edges, and chains that close together.
One cell is selected by default. With several cells, the panel says **Please
select the area or areas you want to extrude.** Either controller can trigger an
area to toggle its orange fill and outline. No selection leaves Apply disabled.
Only selected cells participate in New/Add/Remove, their holes remain empty,
and the arrow/preview uses the same selected cells and depth.

One Apply is one undoable feature and one resulting CAD part, including when
selected cells form disconnected islands. Those islands currently move together;
this is not a full multi-body CAD kernel. Driving edits retain selected cells
while their boundary topology remains identifiable; conflicting or ambiguous
changes roll back. Sketch and region definitions persist through save/load,
part motion, origin movement, and solid-history rebuilds.

Area geometry and fill meshes are cached between edits. Live Add/Remove retains
its existing complexity/latency guard and may fall back to a translucent tool
preview while dragging. It does not run a boolean on every controller frame.


### Solid topology and STL safeguards (1.4.21)
Selected areas that share a boundary are combined in the sketch plane before
extrusion, avoiding internal walls between adjacent cells. Areas touching only
at a point cannot become one CAD part: add a bridge with nonzero thickness or
extrude them separately. Closed disconnected islands remain supported.

New/Add/Remove and dimension-history rebuilds check the resulting surface before
committing. A rejected operation retains the last good model and undo/redo.
Exact zero-area CSG triangles are discarded; nonzero geometry is not repaired
or reshaped. The check handles ordinary CSG T junctions and verifies paired,
oppositely oriented edges and a connected surface fan around each vertex.
It is a topology check, not a general triangle self-intersection solver or a
printer-specific minimum-wall-thickness guarantee.

Older saved designs still load for inspection and repair. Selected-part and
combined menu exports block a part with invalid topology before writing an STL
or queuing a Drive upload, with an explanation and suggested correction.
Assembly parts are checked separately, so separate touching classic blocks do
not become a single welded CAD body. Save files are not silently repaired.

Before public distribution, follow [RELEASE_CHECKLIST.md](../RELEASE_CHECKLIST.md).


### Startup and lighting defaults (1.4.22)
Fresh installs and older saved `enabled=false` defaults now start in CAD.
Only the new explicit Legacy block mode preference opts out. Switching modes
preserves CAD parts, placed blocks, saved builds, and probe calibration.
The old block tutorial is shown only for legacy startup when not dismissed.

Front (`OmniLight3D5`) and Left (`OmniLight3D4`) default off following the
user's Quest confirmation that disabling them removes the black squares.
Other light defaults are unchanged. Both lights remain available in Lights;
restarting restores the off defaults. This avoids the affected lighting path;
it does not change the underlying renderer or CAD geometry.


### Origin-facing base planes (1.4.23)
Dragging the workspace origin with the right trigger turns Front toward the
headset using yaw only, keeping Front upright and Top level. Release freezes
the heading, so looking or walking around afterward does not spin the planes.
The existing workspace translation still moves CAD bodies and their sketches;
changing the base-plane heading does not rotate existing geometry or rewrite
existing sketch frames. New Front/Top/Right sketches use the displayed frames.

The heading is part of CAD save/load and grouped origin-drag Undo/Redo. An
empty workspace with only its heading changed saves as CAD too. Older saves
without a heading keep the previous world-aligned orientation. Captured table
references keep their own frame. View scaling is removed before computing the
heading; looking straight down/up retains the last stable horizontal heading.


### Feature depth editing and dimension label placement
The feature list shows each sketch followed immediately by its Extrude rows,
with the current depth in mm. Select an Extrude row to open that feature's depth
in the floating number pad. Apply rebuilds the existing part and its later
operations; invalid edits retain the last good solid. Undo/Redo includes depth
and geometry. Parts remain listed below the sketch and extrusion history.

In Select / sketch dimension mode, short-click a dimension label to edit its
value. Hold trigger and drag the label to reposition it instead. Release saves
the placement; B or tracking loss cancels the drag. Leaders stay attached to
the measured geometry. Automatic labels separate based on their rendered text
size and viewing angle; explicit placements take priority. Label placements
save/load and undo/redo with the sketch without changing geometry or STL sizes.
